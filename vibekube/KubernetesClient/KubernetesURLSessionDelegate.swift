import Foundation
import Security

final class KubernetesURLSessionDelegate: NSObject, URLSessionDelegate {
    private let insecureSkipTLSVerify: Bool
    private let caCertificates: [SecCertificate]
    private let clientIdentity: TemporaryClientIdentity?

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
        if SecTrustEvaluateWithError(trust, &trustError) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
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

        let importedCertificates = (importedItems as? [Any] ?? [])
            .compactMap { item -> SecCertificate? in
                guard CFGetTypeID(item as CFTypeRef) == SecCertificateGetTypeID() else {
                    return nil
                }
                return (item as! SecCertificate)
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
