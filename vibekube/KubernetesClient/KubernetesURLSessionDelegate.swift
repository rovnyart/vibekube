import Foundation
import Security

final class KubernetesURLSessionDelegate: NSObject, URLSessionDataDelegate {
    private let insecureSkipTLSVerify: Bool
    private let caCertificates: [SecCertificate]
    private let clientIdentity: TemporaryClientIdentity?
    private let streamLock = NSLock()
    private var streamHandlers: [Int: KubernetesStreamingResponseHandler] = [:]
    private let trustErrorLock = NSLock()
    private var lastServerTrustErrorMessage: String?

    init(configuration: KubernetesClientConfiguration) throws {
        self.insecureSkipTLSVerify = configuration.insecureSkipTLSVerify
        self.caCertificates = try configuration.certificateAuthorityData.map(Self.certificates(from:)) ?? []

        if case .clientCertificate(let certificateData, let keyData) = configuration.credential {
            self.clientIdentity = try TemporaryClientIdentity(certificateData: certificateData, keyData: keyData)
        } else {
            self.clientIdentity = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrust(challenge: challenge, completionHandler: completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertificate(completionHandler: completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    func registerStream(
        task: URLSessionDataTask,
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        errorMapper: @escaping (Data, Int) -> KubernetesClientError
    ) {
        streamLock.lock()
        streamHandlers[task.taskIdentifier] = KubernetesStreamingResponseHandler(
            continuation: continuation,
            errorMapper: errorMapper
        )
        streamLock.unlock()
    }

    func unregisterStream(task: URLSessionTask) {
        streamLock.lock()
        streamHandlers.removeValue(forKey: task.taskIdentifier)
        streamLock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let handler = streamHandler(for: dataTask) else {
            completionHandler(.allow)
            return
        }

        if let httpResponse = response as? HTTPURLResponse {
            handler.receive(statusCode: httpResponse.statusCode)
            completionHandler(.allow)
        } else {
            handler.finish(throwing: KubernetesClientError.badResponse)
            unregisterStream(task: dataTask)
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        streamHandler(for: dataTask)?.receive(data: data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let handler = streamHandler(for: task) else {
            return
        }

        unregisterStream(task: task)
        if let error {
            if (error as NSError).code == NSURLErrorCancelled {
                handler.finish()
            } else {
                handler.finish(throwing: KubernetesClientError.unavailable(error.localizedDescription))
            }
        } else {
            handler.finish()
        }
    }

    private func streamHandler(for task: URLSessionTask) -> KubernetesStreamingResponseHandler? {
        streamLock.lock()
        let handler = streamHandlers[task.taskIdentifier]
        streamLock.unlock()
        return handler
    }

    private func handleServerTrust(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        if insecureSkipTLSVerify {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        if !caCertificates.isEmpty {
            SecTrustSetAnchorCertificates(trust, caCertificates as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, true)
        }

        var trustError: CFError?
        var pinnedTrustError: CFError?
        if SecTrustEvaluateWithError(trust, &trustError) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else if !caCertificates.isEmpty, evaluatePinnedClusterTrust(trust, error: &pinnedTrustError) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            recordServerTrustError(pinnedTrustError ?? trustError)
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func evaluatePinnedClusterTrust(_ trust: SecTrust, error: inout CFError?) -> Bool {
        // Teleport and some Kubernetes endpoints present CA-pinned certificates
        // that are valid for Kubernetes clients but fail Apple's stricter
        // browser/server certificate policy. Keep the kubeconfig CA pin, but
        // fall back to basic X.509 chain validation for these cluster certs.
        SecTrustSetPolicies(trust, SecPolicyCreateBasicX509())
        SecTrustSetAnchorCertificates(trust, caCertificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)

        return SecTrustEvaluateWithError(trust, &error)
    }

    func consumeServerTrustErrorMessage() -> String? {
        trustErrorLock.lock()
        let message = lastServerTrustErrorMessage
        lastServerTrustErrorMessage = nil
        trustErrorLock.unlock()
        return message
    }

    private func recordServerTrustError(_ error: CFError?) {
        trustErrorLock.lock()
        lastServerTrustErrorMessage = error.map { CFErrorCopyDescription($0) as String }
            ?? "The server certificate could not be trusted."
        trustErrorLock.unlock()
    }

    private func handleClientCertificate(
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let clientIdentity else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(
            .useCredential,
            URLCredential(
                identity: clientIdentity.identity,
                certificates: clientIdentity.certificates,
                persistence: .forSession
            )
        )
    }

    private static func certificates(from data: Data) throws -> [SecCertificate] {
        let blocks = PEM.blocks(in: data, label: "CERTIFICATE")
        let certificateData = blocks.isEmpty ? [data] : blocks
        let certificates = certificateData.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }

        guard !certificates.isEmpty else {
            throw KubernetesClientError.certificateError("Could not parse certificate authority data.")
        }

        return certificates
    }

}

private final class KubernetesStreamingResponseHandler {
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let errorMapper: (Data, Int) -> KubernetesClientError
    private let lock = NSLock()
    private var statusCode: Int?
    private var pendingText = ""
    private var errorData = Data()
    private var isFinished = false

    init(
        continuation: AsyncThrowingStream<String, Error>.Continuation,
        errorMapper: @escaping (Data, Int) -> KubernetesClientError
    ) {
        self.continuation = continuation
        self.errorMapper = errorMapper
    }

    func receive(statusCode: Int) {
        lock.lock()
        self.statusCode = statusCode
        lock.unlock()
    }

    func receive(data: Data) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        guard let statusCode, (200..<300).contains(statusCode) else {
            errorData.append(data)
            lock.unlock()
            return
        }

        pendingText += String(decoding: data, as: UTF8.self)
        let lines = completeLines()
        lock.unlock()

        for line in lines {
            continuation.yield(line)
        }
    }

    func finish(throwing error: Error? = nil) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true

        if let error {
            lock.unlock()
            continuation.finish(throwing: error)
            return
        }

        if let statusCode, !(200..<300).contains(statusCode) {
            let mappedError = errorMapper(errorData, statusCode)
            lock.unlock()
            continuation.finish(throwing: mappedError)
            return
        }

        let remainder = pendingText
        pendingText = ""
        lock.unlock()

        if !remainder.isEmpty {
            continuation.yield(remainder)
        }
        continuation.finish()
    }

    private func completeLines() -> [String] {
        let parts = pendingText.components(separatedBy: "\n")
        guard parts.count > 1 else {
            return []
        }

        pendingText = parts.last ?? ""
        return parts.dropLast().map { $0 + "\n" }
    }
}

final class TemporaryClientIdentity {
    let identity: SecIdentity
    let certificates: [SecCertificate]

    private let keychain: SecKeychain
    private let keychainURL: URL

    init(certificateData: Data, keyData: Data) throws {
        let keychainURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibekube-\(UUID().uuidString).keychain")
        let password = "vibekube-temporary-keychain"

        var createdKeychain: SecKeychain?
        let createStatus = SecKeychainCreate(
            keychainURL.path,
            UInt32(password.utf8.count),
            password,
            false,
            nil,
            &createdKeychain
        )

        guard createStatus == errSecSuccess, let createdKeychain else {
            throw KubernetesClientError.certificateError("Could not create a temporary keychain for client certificate auth.")
        }

        let combinedPEM = Self.combinedPEM(certificateData: certificateData, keyData: keyData)
        var importedItems: CFArray?
        let importStatus = SecItemImport(
            combinedPEM as CFData,
            nil,
            nil,
            nil,
            SecItemImportExportFlags(rawValue: 0),
            nil,
            createdKeychain,
            &importedItems
        )

        guard importStatus == errSecSuccess else {
            Self.deleteKeychain(createdKeychain, url: keychainURL)
            throw KubernetesClientError.certificateError("Could not import client certificate and key.")
        }

        let importedItemsList = importedItems as? [Any] ?? []
        let importedIdentities = importedItemsList
            .compactMap { item -> SecIdentity? in
                guard CFGetTypeID(item as CFTypeRef) == SecIdentityGetTypeID() else {
                    return nil
                }
                return (item as! SecIdentity)
            }
        let importedCertificates = importedItemsList
            .compactMap { item -> SecCertificate? in
                guard CFGetTypeID(item as CFTypeRef) == SecCertificateGetTypeID() else {
                    return nil
                }
                return (item as! SecCertificate)
            }

        if let importedIdentity = importedIdentities.first {
            self.keychain = createdKeychain
            self.keychainURL = keychainURL
            self.identity = importedIdentity
            self.certificates = importedCertificates
            return
        }

        guard let certificate = importedCertificates.first else {
            Self.deleteKeychain(createdKeychain, url: keychainURL)
            throw KubernetesClientError.certificateError("Client certificate data did not contain a certificate.")
        }

        var createdIdentity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(createdKeychain, certificate, &createdIdentity)
        guard identityStatus == errSecSuccess, let createdIdentity else {
            Self.deleteKeychain(createdKeychain, url: keychainURL)
            throw KubernetesClientError.certificateError("Could not pair client certificate with its private key.")
        }

        self.keychain = createdKeychain
        self.keychainURL = keychainURL
        self.identity = createdIdentity
        self.certificates = importedCertificates
    }

    deinit {
        Self.deleteKeychain(keychain, url: keychainURL)
    }

    private static func combinedPEM(certificateData: Data, keyData: Data) -> Data {
        if PEM.looksLikePEM(certificateData), PEM.looksLikePEM(keyData) {
            var combined = Data()
            combined.append(certificateData)
            if certificateData.last != UInt8(ascii: "\n") {
                combined.append(Data("\n".utf8))
            }
            combined.append(keyData)
            return combined
        }

        let certificatePEM = PEM.encode(data: certificateData, label: "CERTIFICATE")
        let keyPEM = PEM.looksLikePEM(keyData)
            ? String(decoding: keyData, as: UTF8.self)
            : PEM.encode(data: keyData, label: "PRIVATE KEY")
        return Data("\(certificatePEM)\n\(keyPEM)".utf8)
    }

    private static func deleteKeychain(_ keychain: SecKeychain, url: URL) {
        SecKeychainDelete(keychain)
        try? FileManager.default.removeItem(at: url)
    }
}

private enum PEM {
    static func looksLikePEM(_ data: Data) -> Bool {
        guard let string = String(data: data, encoding: .utf8) else {
            return false
        }
        return string.contains("-----BEGIN ") && string.contains("-----END ")
    }

    static func blocks(in data: Data, label: String) -> [Data] {
        guard let string = String(data: data, encoding: .utf8) else {
            return []
        }

        let beginMarker = "-----BEGIN \(label)-----"
        let endMarker = "-----END \(label)-----"
        var remainder = string[...]
        var blocks: [Data] = []

        while let beginRange = remainder.range(of: beginMarker),
              let endRange = remainder[beginRange.upperBound...].range(of: endMarker) {
            let base64 = remainder[beginRange.upperBound..<endRange.lowerBound]
                .components(separatedBy: .whitespacesAndNewlines)
                .joined()

            if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                blocks.append(data)
            }

            remainder = remainder[endRange.upperBound...]
        }

        return blocks
    }

    static func encode(data: Data, label: String) -> String {
        let base64 = data.base64EncodedString()
        let lines = stride(from: 0, to: base64.count, by: 64).map { offset -> String in
            let start = base64.index(base64.startIndex, offsetBy: offset)
            let end = base64.index(start, offsetBy: min(64, base64.distance(from: start, to: base64.endIndex)))
            return String(base64[start..<end])
        }
        return """
        -----BEGIN \(label)-----
        \(lines.joined(separator: "\n"))
        -----END \(label)-----
        """
    }
}
