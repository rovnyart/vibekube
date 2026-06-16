import Foundation

actor DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    private let fileManager: FileManager
    private let logDirectoryURL: URL
    private let bufferLimit: Int
    private var settings: DiagnosticsSettings
    private var events: [DiagnosticsEvent]
    private let encoder: JSONEncoder
    private let exportFormatter: ISO8601DateFormatter
    private let fileDateFormatter: DateFormatter

    init(
        fileManager: FileManager = .default,
        logDirectoryURL: URL? = nil,
        bufferLimit: Int = 1_000
    ) {
        self.fileManager = fileManager
        self.logDirectoryURL = logDirectoryURL ?? Self.defaultLogDirectoryURL(fileManager: fileManager)
        self.bufferLimit = bufferLimit
        self.settings = .default
        self.events = []

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder

        self.exportFormatter = ISO8601DateFormatter()

        let fileDateFormatter = DateFormatter()
        fileDateFormatter.calendar = Calendar(identifier: .gregorian)
        fileDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileDateFormatter.timeZone = .current
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        self.fileDateFormatter = fileDateFormatter
    }

    var logDirectoryPath: String {
        logDirectoryURL.path
    }

    func configure(_ settings: DiagnosticsSettings) async {
        self.settings = DiagnosticsSettings(
            fileLoggingEnabled: settings.fileLoggingEnabled,
            includeClusterNames: settings.includeClusterNames,
            retentionDays: max(1, min(settings.retentionDays, 30)),
            maxTotalMegabytes: max(1, min(settings.maxTotalMegabytes, 500))
        )

        if self.settings.fileLoggingEnabled {
            cleanupLogFiles()
        }
    }

    func record(
        _ level: DiagnosticsLevel,
        category: String,
        message: String,
        contextID: String? = nil,
        contextName: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        let event = DiagnosticsEvent(
            level: level,
            category: category,
            message: message,
            contextHash: DiagnosticsRedactor.hashIdentifier(contextID),
            contextName: settings.includeClusterNames ? contextName : nil,
            metadata: DiagnosticsRedactor.sanitizedMetadata(metadata)
        )

        appendToBuffer(event)

        guard settings.fileLoggingEnabled else {
            return
        }

        writeEventToFile(event)
    }

    func recentEvents() async -> [DiagnosticsEvent] {
        events
    }

    func clearRecentEvents() async {
        events.removeAll()
    }

    func exportText(
        appVersion: String,
        selectedContextID: String?,
        selectedContextName: String?,
        selectedConnectionState: String,
        selectedRoute: String,
        namespace: String,
        kubeconfigState: String
    ) async -> String {
        var lines: [String] = [
            "Vibekube Diagnostics",
            "Generated: \(exportFormatter.string(from: Date()))",
            "App: \(appVersion)",
            "Route: \(selectedRoute)",
            "Connection: \(selectedConnectionState)",
            "Namespace: \(namespace)",
            "Kubeconfig: \(kubeconfigState)",
            "File logging: \(settings.fileLoggingEnabled ? "enabled" : "disabled")",
            "Log directory: \(logDirectoryPath)",
            "Context hash: \(DiagnosticsRedactor.hashIdentifier(selectedContextID) ?? "-")"
        ]

        if settings.includeClusterNames {
            lines.append("Context: \(selectedContextName ?? "-")")
        }

        lines.append("")
        lines.append("Recent Events")

        if events.isEmpty {
            lines.append("- none")
        } else {
            for event in events.suffix(250) {
                lines.append(event.exportLine(formatter: exportFormatter))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func appendToBuffer(_ event: DiagnosticsEvent) {
        events.append(event)
        if events.count > bufferLimit {
            events.removeFirst(events.count - bufferLimit)
        }
    }

    private func writeEventToFile(_ event: DiagnosticsEvent) {
        do {
            try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
            var line = try encoder.encode(event)
            line.append(0x0A)
            let fileURL = logDirectoryURL.appendingPathComponent("vibekube-\(fileDateFormatter.string(from: event.timestamp)).jsonl")

            if fileManager.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL, options: .atomic)
            }

            cleanupLogFiles()
        } catch {
            appendToBuffer(
                DiagnosticsEvent(
                    level: .warning,
                    category: "diagnostics",
                    message: "Could not write diagnostics log file.",
                    metadata: ["error": error.localizedDescription]
                )
            )
        }
    }

    private func cleanupLogFiles() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: logDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let logFiles = urls
            .filter { $0.lastPathComponent.hasPrefix("vibekube-") && $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                (fileDate(for: lhs) ?? .distantPast) < (fileDate(for: rhs) ?? .distantPast)
            }

        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.retentionDays, to: Date()) ?? .distantPast
        for file in logFiles where (fileDate(for: file) ?? .distantPast) < cutoff {
            try? fileManager.removeItem(at: file)
        }

        var remainingFiles = logFiles.filter { fileManager.fileExists(atPath: $0.path) }
        var totalBytes = remainingFiles.reduce(0) { partialResult, url in
            partialResult + fileSize(url)
        }
        let maximumBytes = settings.maxTotalMegabytes * 1_024 * 1_024

        while totalBytes > maximumBytes, let oldest = remainingFiles.first {
            totalBytes -= fileSize(oldest)
            try? fileManager.removeItem(at: oldest)
            remainingFiles.removeFirst()
        }
    }

    private func fileDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate ?? values?.creationDate
    }

    private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize ?? 0
    }

    static func defaultLogDirectoryURL(fileManager: FileManager = .default) -> URL {
        let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first ??
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return libraryURL.appendingPathComponent("Logs/Vibekube", isDirectory: true)
    }
}

nonisolated private extension DiagnosticsEvent {
    func exportLine(formatter: ISO8601DateFormatter) -> String {
        var fields = [
            formatter.string(from: timestamp),
            level.rawValue.uppercased(),
            category,
            message
        ]

        if let contextHash {
            fields.append("context=\(contextHash)")
        }
        if let contextName {
            fields.append("contextName=\(contextName)")
        }
        if !metadata.isEmpty {
            fields.append(
                metadata.keys.sorted()
                    .map { "\($0)=\(metadata[$0] ?? "")" }
                    .joined(separator: " ")
            )
        }

        return fields.joined(separator: " | ")
    }
}
