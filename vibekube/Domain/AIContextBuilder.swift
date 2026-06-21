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
        eventState: ResourceEventsLoadState,
        logSnapshots: [PodLogSnapshot] = []
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

        let relatedText = relatedResourcesText(summary)
        if !relatedText.isEmpty {
            sections.append(AIContextSection(title: "Related Resources", content: relatedText))
        }

        if !summary.environment.isEmpty {
            sections.append(
                AIContextSection(
                    title: "Environment",
                    content: summary.environment.prefix(8).map(environmentText).joined(separator: "\n")
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

        if !logSnapshots.isEmpty {
            sections.append(
                AIContextSection(
                    title: "Selected Log Snippets",
                    content: logSnapshots.prefix(3).map(logText).joined(separator: "\n\n")
                )
            )
        }

        sections.append(
            AIContextSection(
                title: "Redacted YAML",
                content: limitedText(
                    AIContextRedactor.redactedManifest(detail.yaml, kind: summary.kind),
                    maxCharacters: 14_000
                )
            )
        )

        return AIContextBundle(
            title: title,
            identity: identityLines.joined(separator: "\n"),
            sections: limitedSections(sections)
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

    private static func relatedResourcesText(_ summary: KubernetesResourceDetailSummary) -> String {
        var lines: [String] = []

        for owner in summary.ownerReferences.prefix(8) {
            lines.append("- owner \(owner.kind)/\(owner.name)")
        }

        if let selector = summary.labelSelector, !selector.displayText.isEmpty {
            lines.append("- selector \(AIContextRedactor.redactedText(selector.displayText))")
        }

        for reference in summary.configMapReferences.prefix(10) {
            lines.append("- ConfigMap/\(reference.name) \(reference.detail)")
        }

        for reference in summary.secretReferences.prefix(10) {
            lines.append("- Secret/\(reference.name) \(reference.detail)")
        }

        if let persistentVolumeName = summary.persistentVolumeName {
            lines.append("- PersistentVolume/\(persistentVolumeName)")
        }

        for service in summary.ingressServices.prefix(10) {
            lines.append("- Service/\(service.name) \(service.route)")
        }

        return lines.joined(separator: "\n")
    }

    private static func environmentText(_ container: KubernetesContainerEnvironmentSummary) -> String {
        var lines = ["Container: \(container.containerName)"]

        for source in container.envFrom.prefix(8) {
            lines.append("- envFrom \(source.kind.rawValue)/\(source.name)\(source.prefix.map { " prefix=\($0)" } ?? "")")
        }

        for variable in container.variables.prefix(20) {
            lines.append(environmentVariableText(variable))
        }

        return lines.joined(separator: "\n")
    }

    private static func environmentVariableText(_ variable: KubernetesEnvVarSummary) -> String {
        if let source = variable.source {
            let name = source.name ?? "-"
            let key = source.key ?? "-"
            return "- \(variable.name)=<from \(source.kind.rawValue) \(name)/\(key)>"
        }

        let value = variable.literalValue ?? ""
        let redactedValue = shouldRedactEnvironmentValue(name: variable.name, value: value)
            ? "<redacted>"
            : AIContextRedactor.redactedText(value)
        return "- \(variable.name)=\(redactedValue)"
    }

    private static func shouldRedactEnvironmentValue(name: String, value: String) -> Bool {
        let sensitiveFragments = [
            "api_key",
            "apikey",
            "auth",
            "bearer",
            "client_secret",
            "credential",
            "password",
            "private",
            "secret",
            "token"
        ]
        let normalizedName = name.lowercased()
        if sensitiveFragments.contains(where: { normalizedName.contains($0) }) {
            return true
        }

        return AIContextRedactor.redactedText(value) != value
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

    private static func logText(_ snapshot: PodLogSnapshot) -> String {
        let lines = snapshot.lines.suffix(120).joined(separator: "\n")
        let redacted = AIContextRedactor.redactedText(lines)
        return limitedText(
            "Log: \(snapshot.query.title)\n\(redacted)",
            maxCharacters: 8_000
        )
    }

    private static func limitedSections(_ sections: [AIContextSection]) -> [AIContextSection] {
        var remainingCharacters = 32_000
        var limited: [AIContextSection] = []

        for section in sections {
            guard remainingCharacters > 0 else {
                break
            }

            let contentLimit = min(section.content.count, remainingCharacters)
            let content = limitedText(section.content, maxCharacters: contentLimit)
            remainingCharacters -= content.count
            limited.append(AIContextSection(id: section.id, title: section.title, content: content))
        }

        if limited.count < sections.count {
            limited.append(
                AIContextSection(
                    title: "Context Limit",
                    content: "Additional context sections were omitted because the prompt reached Vibekube's local size limit."
                )
            )
        }

        return limited
    }

    private static func limitedText(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else {
            return text
        }

        let prefixCount = max(0, maxCharacters - 120)
        let index = text.index(text.startIndex, offsetBy: prefixCount)
        return String(text[..<index]) + "\n<truncated by Vibekube before AI request>"
    }
}
