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
            message: "Exec credential failed.",
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
    }
}
