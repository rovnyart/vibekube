import Foundation

enum AIContextRedactor {
    static func redactedManifest(_ yaml: String, kind: String?) -> String {
        let secretRedacted = kind == "Secret" ? redactSecretBlocks(in: yaml) : yaml
        return DiagnosticsRedactor.redactedText(secretRedacted)
    }

    static func redactedText(_ text: String) -> String {
        DiagnosticsRedactor.redactedText(text)
    }

    private static func redactSecretBlocks(in yaml: String) -> String {
        let sensitiveKeys = ["data", "stringData", "binaryData"]
        var output: [String] = []
        var redactingIndent: Int?

        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count

            if let activeIndent = redactingIndent {
                if trimmed.isEmpty || indent > activeIndent {
                    if trimmed.hasPrefix("-") {
                        output.append(String(line.prefix(indent)) + "- <redacted>")
                    } else if let colonIndex = line.firstIndex(of: ":") {
                        let key = String(line[..<colonIndex])
                        output.append("\(key): <redacted>")
                    } else {
                        output.append(String(line.prefix(indent)) + "<redacted>")
                    }
                    continue
                }
                redactingIndent = nil
            }

            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex])
                if sensitiveKeys.contains(key) {
                    redactingIndent = indent
                    output.append(String(line.prefix(indent)) + "\(key):")
                    continue
                }
            }

            output.append(line)
        }

        return output.joined(separator: "\n")
    }
}

enum AIContextBuilder {
    static func resourceContext(
        detail: ResourceDetailSnapshot,
        cluster: ClusterSummary?,
        namespaceTitle: String,
        eventState: ResourceEventsLoadState
    ) -> AIContextBundle {
        let summary = detail.summary
        let kind = summary.kind ?? detail.query.resource.kind
        let name = summary.name ?? detail.query.name
        let namespace = summary.namespace ?? detail.query.namespace ?? namespaceTitle
        let title = "\(kind)/\(name)"

        var identityLines = [
            "Resource: \(title)",
            "Namespace: \(namespace)",
            "API: \(detail.query.resource.groupVersion)/\(detail.query.resource.name)"
        ]
        if let cluster {
            identityLines.insert("Cluster context: \(cluster.contextName)", at: 0)
        }
        if let status = summary.status {
            identityLines.append("Status: \(status)")
        }

        var sections: [AIContextSection] = []
        sections.append(AIContextSection(title: "Identity", content: identityLines.joined(separator: "\n")))

        if let debugSummary = summary.debugSummary {
            sections.append(
                AIContextSection(
                    title: "Debug Summary",
                    content: debugSummaryText(debugSummary)
                )
            )
        }

        if !summary.conditions.isEmpty {
            sections.append(
                AIContextSection(
                    title: "Conditions",
                    content: summary.conditions.prefix(12).map(conditionText).joined(separator: "\n")
                )
            )
        }

        if !summary.containers.isEmpty {
            sections.append(
                AIContextSection(
                    title: "Containers",
                    content: summary.containers.prefix(12).map(containerText).joined(separator: "\n")
                )
            )
        }

        if case .loaded(let events) = eventState, !events.events.isEmpty {
            sections.append(
                AIContextSection(
                    title: "Recent Events",
                    content: events.events.prefix(12).map(eventText).joined(separator: "\n")
                )
            )
        }

        sections.append(
            AIContextSection(
                title: "Redacted YAML",
                content: AIContextRedactor.redactedManifest(detail.yaml, kind: summary.kind)
            )
        )

        return AIContextBundle(
            title: title,
            identity: identityLines.joined(separator: "\n"),
            sections: sections
        )
    }

    private static func debugSummaryText(_ summary: KubernetesResourceDebugSummary) -> String {
        var lines = [
            "Severity: \(summary.severity)",
            "Title: \(AIContextRedactor.redactedText(summary.title))",
            "Message: \(AIContextRedactor.redactedText(summary.message))"
        ]

        for signal in summary.signals.prefix(10) {
            lines.append("- [\(signal.severity)] \(AIContextRedactor.redactedText(signal.title)): \(AIContextRedactor.redactedText(signal.detail))")
        }

        return lines.joined(separator: "\n")
    }

    private static func conditionText(_ condition: KubernetesConditionSummary) -> String {
        [
            "- \(condition.type)=\(condition.status)",
            condition.reason.map { "reason=\(AIContextRedactor.redactedText($0))" },
            condition.message.map { "message=\(AIContextRedactor.redactedText($0))" },
            condition.lastTransitionTime.map { "lastTransition=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func containerText(_ container: KubernetesContainerSummary) -> String {
        let state = container.currentState?.title ?? "unknown"
        return [
            "- \(container.name)",
            "ready=\(container.ready.map(String.init) ?? "unknown")",
            "started=\(container.started.map(String.init) ?? "unknown")",
            "restarts=\(container.restartCount.map(String.init) ?? "unknown")",
            "state=\(AIContextRedactor.redactedText(state))",
            container.currentState?.reason.map { "reason=\(AIContextRedactor.redactedText($0))" },
            container.currentState?.message.map { "message=\(AIContextRedactor.redactedText($0))" }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private static func eventText(_ event: KubernetesResourceEventSummary) -> String {
        [
            "- \(event.type)",
            "reason=\(AIContextRedactor.redactedText(event.reason))",
            "count=\(event.count.map(String.init) ?? "unknown")",
            event.lastObserved.map { "last=\($0)" },
            "message=\(AIContextRedactor.redactedText(event.message))"
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}
