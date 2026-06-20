import Foundation
import Testing
@testable import vibekube

struct DiagnosticsTests {
    @Test func diagnosticsLoggerRedactsAndWritesJsonLines() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vibekube-diagnostics-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let logger = DiagnosticsLogger(logDirectoryURL: directory, bufferLimit: 3)
        await logger.configure(
            DiagnosticsSettings(
                fileLoggingEnabled: true,
                includeClusterNames: false,
                retentionDays: 7,
                maxTotalMegabytes: 1
            )
        )

        await logger.record(
            .error,
            category: "auth",
            message: "Exec credential failed: Bearer super-secret-token",
            contextID: "prod-context",
            contextName: "prod-context",
            metadata: [
                "resource": "pods",
                "token": "super-secret-token",
                "raw": "Bearer super-secret-token"
            ]
        )

        let events = await logger.recentEvents()
        let event = try #require(events.first)
        #expect(event.contextHash != nil)
        #expect(event.contextName == nil)
        #expect(event.message == "Exec credential failed: Bearer <redacted>")
        #expect(event.metadata["resource"] == "pods")
        #expect(event.metadata["token"] == "<redacted>")
        #expect(event.metadata["raw"] == "<redacted>")

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let logFile = try #require(files.first { $0.pathExtension == "jsonl" })
        let contents = try String(contentsOf: logFile, encoding: .utf8)
        #expect(contents.contains(#""category":"auth""#))
        #expect(contents.contains("<redacted>"))
        #expect(!contents.contains("super-secret-token"))
        #expect(!contents.contains("prod-context"))

        let export = await logger.exportText(
            appVersion: "0.1.0 (1)",
            selectedContextID: "prod-context",
            selectedContextName: "prod-context",
            selectedConnectionState: "unavailable",
            selectedRoute: "Dashboard",
            namespace: "All Namespaces",
            kubeconfigState: "loaded contexts=1 sources=1"
        )
        #expect(export.contains("Context hash:"))
        #expect(!export.contains("Context: prod-context"))
        #expect(!export.contains("super-secret-token"))
    }

    @Test func diagnosticsRedactorRedactsFreeformSecretText() {
        let privateKey = """
        -----BEGIN PRIVATE KEY-----
        abc123
        -----END PRIVATE KEY-----
        """
        let text = """
        request failed Authorization: Bearer super-secret-token token=raw-token --password hunter2 client-key-data: LS0tCg== \(privateKey)
        """

        let redacted = DiagnosticsRedactor.redactedText(text)

        #expect(redacted.contains("Bearer <redacted>"))
        #expect(redacted.contains("token=<redacted>"))
        #expect(redacted.contains("--password <redacted>"))
        #expect(redacted.contains("client-key-data: <redacted>"))
        #expect(!redacted.contains("super-secret-token"))
        #expect(!redacted.contains("raw-token"))
        #expect(!redacted.contains("hunter2"))
        #expect(!redacted.contains("LS0tCg=="))
        #expect(!redacted.contains("abc123"))
    }

    @Test func kubernetesClientErrorDescriptionsRedactSensitiveStatusMessages() {
        let error = KubernetesClientError.statusCode(
            422,
            "admission denied token=super-secret-token Authorization: Bearer bearer-secret"
        )

        let message = error.localizedDescription

        #expect(message.contains("HTTP 422"))
        #expect(message.contains("token=<redacted>"))
        #expect(message.contains("Bearer <redacted>"))
        #expect(!message.contains("super-secret-token"))
        #expect(!message.contains("bearer-secret"))
    }
}
