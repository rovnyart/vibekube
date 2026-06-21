import Foundation

struct KubernetesResourceDetail: Decodable, Equatable {
    var value: KubernetesJSONValue

    init(value: KubernetesJSONValue) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        self.value = try KubernetesJSONValue(from: decoder)
    }

    nonisolated var kind: String? {
        value["kind"]?.stringValue
    }

    nonisolated var yaml: String {
        KubernetesYAMLRenderer.render(
            value,
            redactedTopLevelKeys: isSecret ? ["binaryData", "data", "stringData"] : []
        )
    }

    nonisolated func decodedSecretValue(forKey key: String) -> String? {
        guard isSecret else {
            return nil
        }

        if let value = value["stringData"]?[key]?.stringValue {
            return value
        }

        guard let encodedValue = value["data"]?[key]?.stringValue,
              let data = Data(base64Encoded: encodedValue) else {
            return nil
        }

        return String(decoding: data, as: UTF8.self)
    }

    nonisolated var configMapValues: [String: String] {
        guard kind == "ConfigMap" else {
            return [:]
        }

        var values = Self.stringValues(in: value["data"])
        for (key, value) in Self.base64Values(in: value["binaryData"]) {
            values[key] = value
        }
        return values
    }

    nonisolated var secretKeys: [String] {
        guard isSecret else {
            return []
        }

        let dataKeys = value["data"]?.objectValue.map { Array($0.keys) } ?? []
        let stringDataKeys = value["stringData"]?.objectValue.map { Array($0.keys) } ?? []
        return Array(Set(dataKeys).union(stringDataKeys)).sorted()
    }

    nonisolated var summary: KubernetesResourceDetailSummary {
        KubernetesResourceDetailSummary(value: value)
    }

    private nonisolated var isSecret: Bool {
        kind == "Secret"
    }

    private nonisolated static func stringValues(in value: KubernetesJSONValue?) -> [String: String] {
        guard let object = value?.objectValue else {
            return [:]
        }

        return object.reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value.displayValue
        }
    }

    private nonisolated static func base64Values(in value: KubernetesJSONValue?) -> [String: String] {
        guard let object = value?.objectValue else {
            return [:]
        }

        return object.reduce(into: [:]) { result, entry in
            guard let encodedValue = entry.value.stringValue,
                  let data = Data(base64Encoded: encodedValue) else {
                return
            }

            result[entry.key] = String(data: data, encoding: .utf8) ?? "<binary data>"
        }
    }
}

struct KubernetesResourceDetailSummary: Equatable {
    var apiVersion: String?
    var kind: String?
    var name: String?
    var namespace: String?
    var uid: String?
    var resourceVersion: String?
    var creationTimestamp: String?
    var deletionTimestamp: String?
    var status: String?
    var type: String?
    var labels: [String: String]
    var annotations: [String: String]
    var ownerReferences: [KubernetesOwnerReferenceSummary]
    var labelSelector: KubernetesLabelSelectorSummary?
    var ingressServices: [KubernetesIngressServiceBackendSummary]
    var persistentVolumeName: String?
    var configMapReferences: [KubernetesResourceReferenceSummary]
    var secretReferences: [KubernetesResourceReferenceSummary]
    var portForwardTargets: [KubernetesPortForwardTargetSummary]
    var conditions: [KubernetesConditionSummary]
    var containers: [KubernetesContainerSummary]
    var environment: [KubernetesContainerEnvironmentSummary]
    var podScheduling: KubernetesPodSchedulingSummary?
    var debugSummary: KubernetesResourceDebugSummary?

    init(value: KubernetesJSONValue) {
        let metadata = value["metadata"]
        let spec = value["spec"]
        let statusObject = value["status"]
        let kind = value["kind"]?.stringValue

        self.apiVersion = value["apiVersion"]?.stringValue
        self.kind = kind
        self.name = metadata?["name"]?.stringValue
        self.namespace = metadata?["namespace"]?.stringValue
        self.uid = metadata?["uid"]?.stringValue
        self.resourceVersion = metadata?["resourceVersion"]?.stringValue
        self.creationTimestamp = metadata?["creationTimestamp"]?.stringValue
        self.deletionTimestamp = metadata?["deletionTimestamp"]?.stringValue
        let status = Self.statusText(value: value)
        let conditions = Self.conditions(in: statusObject)
        let containers = Self.containers(in: spec, status: statusObject)

        self.status = status
        self.type = value["type"]?.stringValue
        self.labels = Self.stringMap(metadata?["labels"], redactingValues: false, kind: kind)
        self.annotations = Self.stringMap(metadata?["annotations"], redactingValues: true, kind: kind)
        self.ownerReferences = Self.ownerReferences(in: metadata)
        self.labelSelector = Self.labelSelector(in: spec, kind: kind)
        self.ingressServices = Self.ingressServices(in: spec, kind: kind)
        self.persistentVolumeName = Self.persistentVolumeName(in: spec, kind: kind)
        self.configMapReferences = Self.resourceReferences(in: spec, kind: kind, referenceKind: .configMap)
        self.secretReferences = Self.resourceReferences(in: spec, kind: kind, referenceKind: .secret)
        self.portForwardTargets = Self.portForwardTargets(value: value, kind: kind)
        self.conditions = conditions
        self.containers = containers
        self.environment = Self.environment(in: spec)
        self.podScheduling = Self.podScheduling(in: value, kind: kind)
        self.debugSummary = Self.debugSummary(
            value: value,
            kind: kind,
            status: status,
            conditions: conditions,
            containers: containers
        )
    }

    nonisolated private static func statusText(value: KubernetesJSONValue) -> String? {
        if let phase = value["status"]?["phase"]?.stringValue, !phase.isEmpty {
            return phase
        }

        if let reason = value["reason"]?.stringValue, !reason.isEmpty {
            return reason
        }

        if let type = value["type"]?.stringValue, !type.isEmpty {
            return type
        }

        let readyReplicas = value["status"]?["readyReplicas"]?.intValue ??
            value["status"]?["availableReplicas"]?.intValue ??
            value["status"]?["numberReady"]?.intValue
        let desiredReplicas = value["spec"]?["replicas"]?.intValue ??
            value["status"]?["desiredNumberScheduled"]?.intValue ??
            value["status"]?["replicas"]?.intValue

        if let readyReplicas, let desiredReplicas {
            return "\(readyReplicas)/\(desiredReplicas) ready"
        }

        return nil
    }

    nonisolated private static func stringMap(
        _ value: KubernetesJSONValue?,
        redactingValues: Bool,
        kind: String?
    ) -> [String: String] {
        guard let object = value?.objectValue else {
            return [:]
        }

        var result: [String: String] = [:]
        for (key, value) in object {
            let displayValue = value.displayValue
            result[key] = redactingValues && shouldRedactMetadataValue(key: key, kind: kind)
                ? "<redacted>"
                : displayValue
        }
        return result
    }

    nonisolated private static func shouldRedactMetadataValue(key: String, kind: String?) -> Bool {
        if kind == "Secret" {
            return true
        }

        let sensitiveFragments = [
            "authorization",
            "client-key",
            "credential",
            "kubeconfig",
            "last-applied-configuration",
            "password",
            "secret",
            "token"
        ]
        let lowercasedKey = key.lowercased()
        return sensitiveFragments.contains { lowercasedKey.contains($0) }
    }

    nonisolated private static func ownerReferences(in metadata: KubernetesJSONValue?) -> [KubernetesOwnerReferenceSummary] {
        metadata?["ownerReferences"]?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else {
                return nil
            }

            return KubernetesOwnerReferenceSummary(
                kind: object["kind"]?.stringValue ?? "-",
                name: object["name"]?.stringValue ?? "-",
                controller: object["controller"]?.boolValue ?? false
            )
        } ?? []
    }

    nonisolated private static func labelSelector(
        in spec: KubernetesJSONValue?,
        kind: String?
    ) -> KubernetesLabelSelectorSummary? {
        let selector: KubernetesJSONValue?
        if kind == "Service" {
            selector = spec?["selector"]
        } else {
            selector = spec?["selector"]?["matchLabels"]
        }

        let matchLabels = stringMap(selector, redactingValues: false, kind: kind)
        guard !matchLabels.isEmpty else {
            return nil
        }

        return KubernetesLabelSelectorSummary(matchLabels: matchLabels)
    }

    nonisolated private static func ingressServices(
        in spec: KubernetesJSONValue?,
        kind: String?
    ) -> [KubernetesIngressServiceBackendSummary] {
        guard kind == "Ingress", let spec else {
            return []
        }

        var services: [KubernetesIngressServiceBackendSummary] = []
        if let backend = serviceBackend(in: spec["defaultBackend"], route: "Default backend") {
            services.append(backend)
        }

        for rule in spec["rules"]?.arrayValue ?? [] {
            let host = rule["host"]?.stringValue
            for path in rule["http"]?["paths"]?.arrayValue ?? [] {
                guard let backend = serviceBackend(
                    in: path["backend"],
                    route: ingressRouteText(host: host, path: path["path"]?.stringValue)
                ) else {
                    continue
                }
                services.append(backend)
            }
        }

        var seenNames: Set<String> = []
        return services.filter { backend in
            seenNames.insert(backend.name).inserted
        }
    }

    nonisolated private static func serviceBackend(
        in backend: KubernetesJSONValue?,
        route: String
    ) -> KubernetesIngressServiceBackendSummary? {
        let name = backend?["service"]?["name"]?.stringValue ??
            backend?["serviceName"]?.stringValue
        guard let name, !name.isEmpty else {
            return nil
        }

        return KubernetesIngressServiceBackendSummary(name: name, route: route)
    }

    nonisolated private static func ingressRouteText(host: String?, path: String?) -> String {
        let hostText = host?.isEmpty == false ? host : "*"
        let pathText = path?.isEmpty == false ? path : "/"
        return "\(hostText ?? "*") \(pathText ?? "/")"
    }

    nonisolated private static func persistentVolumeName(
        in spec: KubernetesJSONValue?,
        kind: String?
    ) -> String? {
        guard kind == "PersistentVolumeClaim",
              let volumeName = spec?["volumeName"]?.stringValue,
              !volumeName.isEmpty else {
            return nil
        }

        return volumeName
    }

    nonisolated private static func resourceReferences(
        in spec: KubernetesJSONValue?,
        kind: String?,
        referenceKind: KubernetesReferencedResourceKind
    ) -> [KubernetesResourceReferenceSummary] {
        guard kind == "Pod", let spec else {
            return []
        }

        var referencesByName: [String: Set<String>] = [:]
        func append(name: String?, detail: String) {
            guard let name, !name.isEmpty else {
                return
            }

            referencesByName[name, default: []].insert(detail)
        }

        let podContainers = (spec["initContainers"]?.arrayValue ?? []) +
            (spec["containers"]?.arrayValue ?? []) +
            (spec["ephemeralContainers"]?.arrayValue ?? [])

        for container in podContainers {
            for env in container["env"]?.arrayValue ?? [] {
                let envName = env["name"]?.stringValue ?? "env"
                let valueFrom = env["valueFrom"]
                switch referenceKind {
                case .configMap:
                    append(name: valueFrom?["configMapKeyRef"]?["name"]?.stringValue, detail: "env \(envName)")
                case .secret:
                    append(name: valueFrom?["secretKeyRef"]?["name"]?.stringValue, detail: "env \(envName)")
                }
            }

            for envFrom in container["envFrom"]?.arrayValue ?? [] {
                switch referenceKind {
                case .configMap:
                    append(name: envFrom["configMapRef"]?["name"]?.stringValue, detail: "envFrom")
                case .secret:
                    append(name: envFrom["secretRef"]?["name"]?.stringValue, detail: "envFrom")
                }
            }
        }

        for volume in spec["volumes"]?.arrayValue ?? [] {
            let volumeName = volume["name"]?.stringValue ?? "volume"
            switch referenceKind {
            case .configMap:
                append(name: volume["configMap"]?["name"]?.stringValue, detail: "volume \(volumeName)")
            case .secret:
                append(name: volume["secret"]?["secretName"]?.stringValue, detail: "volume \(volumeName)")
            }
        }

        return referencesByName
            .map { name, details in
                KubernetesResourceReferenceSummary(
                    name: name,
                    detail: details.sorted().joined(separator: ", ")
                )
            }
            .sorted { lhs, rhs in lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
    }

    nonisolated private static func conditions(in status: KubernetesJSONValue?) -> [KubernetesConditionSummary] {
        status?["conditions"]?.arrayValue?.compactMap { value in
            guard let object = value.objectValue else {
                return nil
            }

            return KubernetesConditionSummary(
                type: object["type"]?.stringValue ?? "-",
                status: object["status"]?.stringValue ?? "-",
                reason: object["reason"]?.stringValue,
                message: object["message"]?.stringValue,
                lastTransitionTime: object["lastTransitionTime"]?.stringValue ??
                    object["lastUpdateTime"]?.stringValue
            )
        } ?? []
    }

    nonisolated private static func portForwardTargets(
        value: KubernetesJSONValue,
        kind: String?
    ) -> [KubernetesPortForwardTargetSummary] {
        let metadata = value["metadata"]
        guard let kind,
              let resourceKind = KubernetesPortForwardTargetSummary.resourceKind(forKubernetesKind: kind),
              let resourceName = metadata?["name"]?.stringValue,
              !resourceName.isEmpty else {
            return []
        }

        let namespace = metadata?["namespace"]?.stringValue
        let portValues: [KubernetesJSONValue]
        switch kind {
        case "Pod":
            portValues = containerPortValues(in: value["spec"])
        case "Deployment":
            portValues = containerPortValues(in: value["spec"]?["template"]?["spec"])
        case "Service":
            portValues = value["spec"]?["ports"]?.arrayValue ?? []
        default:
            portValues = []
        }

        let targets = portValues.compactMap { portValue -> KubernetesPortForwardTargetSummary? in
            guard let object = portValue.objectValue else {
                return nil
            }

            let remotePort = kind == "Service"
                ? object["port"]?.intValue
                : object["containerPort"]?.intValue
            guard let remotePort, remotePort > 0 else {
                return nil
            }

            return KubernetesPortForwardTargetSummary(
                resourceKind: resourceKind,
                resourceName: resourceName,
                namespace: namespace,
                portName: object["name"]?.stringValue,
                localPort: KubernetesPortForwardTargetSummary.defaultLocalPort(forRemotePort: remotePort),
                remotePort: remotePort,
                protocolName: object["protocol"]?.stringValue
            )
        }

        var seen: Set<String> = []
        return targets.filter { target in
            seen.insert(target.id).inserted
        }
    }

    nonisolated private static func containerPortValues(in podSpec: KubernetesJSONValue?) -> [KubernetesJSONValue] {
        (podSpec?["containers"]?.arrayValue ?? []).flatMap { container in
            container["ports"]?.arrayValue ?? []
        }
    }

    nonisolated private static func containers(
        in spec: KubernetesJSONValue?,
        status: KubernetesJSONValue?
    ) -> [KubernetesContainerSummary] {
        let containers = containerSummaries(
            in: spec?["containers"]?.arrayValue,
            statuses: status?["containerStatuses"]?.arrayValue,
            kind: .container
        )
        let initContainers = containerSummaries(
            in: spec?["initContainers"]?.arrayValue,
            statuses: status?["initContainerStatuses"]?.arrayValue,
            kind: .initContainer
        )
        let ephemeralContainers = containerSummaries(
            in: spec?["ephemeralContainers"]?.arrayValue,
            statuses: status?["ephemeralContainerStatuses"]?.arrayValue,
            kind: .ephemeralContainer
        )

        return initContainers + containers + ephemeralContainers
    }

    nonisolated private static func podScheduling(
        in value: KubernetesJSONValue,
        kind: String?
    ) -> KubernetesPodSchedulingSummary? {
        guard kind == "Pod" else {
            return nil
        }

        return KubernetesPodSchedulingSummary(
            nodeName: value["spec"]?["nodeName"]?.stringValue,
            nominatedNodeName: value["status"]?["nominatedNodeName"]?.stringValue,
            qosClass: value["status"]?["qosClass"]?.stringValue
        )
    }

    nonisolated private static func debugSummary(
        value: KubernetesJSONValue,
        kind: String?,
        status: String?,
        conditions: [KubernetesConditionSummary],
        containers: [KubernetesContainerSummary]
    ) -> KubernetesResourceDebugSummary? {
        guard let kind, debugSupportedKinds.contains(kind) else {
            return nil
        }

        var signals: [KubernetesResourceDebugSignal] = []
        let statusObject = value["status"]
        let spec = value["spec"]

        if value["metadata"]?["deletionTimestamp"]?.stringValue != nil {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .warning,
                    title: "Resource is terminating",
                    detail: "Kubernetes has set a deletion timestamp; cleanup or finalizers may still be running."
                )
            )
        }

        appendStatusSignals(status: status, kind: kind, signals: &signals)
        appendSchedulingSignals(value: value, kind: kind, status: status, containers: containers, signals: &signals)
        appendContainerSignals(containers, signals: &signals)
        appendConditionSignals(conditions, signals: &signals)
        appendReplicaSignals(kind: kind, spec: spec, status: statusObject, signals: &signals)
        appendJobSignals(kind: kind, status: statusObject, signals: &signals)

        let deduplicatedSignals = deduplicatedDebugSignals(signals)
        let severity = deduplicatedSignals.map(\.severity).max() ?? .healthy
        return KubernetesResourceDebugSummary(
            severity: severity,
            title: debugTitle(for: severity, kind: kind),
            message: debugMessage(for: severity, kind: kind, signalCount: deduplicatedSignals.count),
            signals: deduplicatedSignals
        )
    }

    nonisolated private static let debugSupportedKinds: Set<String> = [
        "CronJob",
        "DaemonSet",
        "Deployment",
        "Job",
        "Pod",
        "ReplicaSet",
        "StatefulSet"
    ]

    nonisolated private static func appendStatusSignals(
        status: String?,
        kind: String,
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        guard let status, !status.isEmpty else {
            return
        }

        let lowercasedStatus = status.lowercased()
        if lowercasedStatus == "failed" {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .critical,
                    title: "\(kind) status is Failed",
                    detail: "Open Events and YAML to inspect the failure reason reported by Kubernetes."
                )
            )
        } else if lowercasedStatus == "pending" {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .warning,
                    title: "\(kind) status is Pending",
                    detail: "Scheduling, image pull, volume mount, or init container work may still be blocking startup."
                )
            )
        }
    }

    nonisolated private static func appendSchedulingSignals(
        value: KubernetesJSONValue,
        kind: String,
        status: String?,
        containers: [KubernetesContainerSummary],
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        guard kind == "Pod" else {
            return
        }

        let spec = value["spec"]
        let statusObject = value["status"]
        let nodeName = spec?["nodeName"]?.stringValue
        let nominatedNodeName = statusObject?["nominatedNodeName"]?.stringValue
        let qosClass = statusObject?["qosClass"]?.stringValue

        if status?.localizedCaseInsensitiveCompare("Pending") == .orderedSame,
           nodeName?.isEmpty != false {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .warning,
                    title: "Pod has not been scheduled",
                    detail: nominatedNodeName?.isEmpty == false
                        ? "Kubernetes nominated node \(nominatedNodeName ?? "-"), but the pod is not bound yet."
                        : "No nodeName is assigned yet. Check PodScheduled condition and scheduler Events."
                )
            )
        }

        if qosClass == "BestEffort" {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .warning,
                    title: "Pod QoS is BestEffort",
                    detail: "No effective CPU or memory requests are set. This pod is first in line for eviction under node pressure."
                )
            )
        }

        let appContainersWithoutRequests = containers.filter { container in
            container.kind == .container && container.resources.requests.isEmpty
        }
        if !appContainersWithoutRequests.isEmpty {
            let names = appContainersWithoutRequests.map(\.name).joined(separator: ", ")
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .warning,
                    title: "Missing resource requests",
                    detail: "Container\(appContainersWithoutRequests.count == 1 ? "" : "s") \(names) do not set CPU or memory requests, which can affect scheduling and eviction behavior."
                )
            )
        }
    }

    nonisolated private static func appendContainerSignals(
        _ containers: [KubernetesContainerSummary],
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        for container in containers {
            if let state = container.currentState {
                switch state.kind {
                case .waiting:
                    signals.append(
                        KubernetesResourceDebugSignal(
                            severity: criticalWaitingReasons.contains(state.reason ?? "") ? .critical : .warning,
                            title: "\(container.name) is waiting\(state.reason.map { ": \($0)" } ?? "")",
                            detail: state.message ?? "Inspect container details, Events, and YAML for the blocked startup path."
                        )
                    )
                case .terminated:
                    if container.kind == .initContainer,
                       state.exitCode == 0,
                       state.reason == "Completed" {
                        break
                    }

                    let exitText = state.exitCode.map { "exit \($0)" } ?? "terminated"
                    signals.append(
                        KubernetesResourceDebugSignal(
                            severity: state.exitCode == 0 ? .warning : .critical,
                            title: "\(container.name) terminated (\(exitText))",
                            detail: state.message ?? state.reason ?? "Open Logs or Previous Logs to inspect the terminated process."
                        )
                    )
                case .running:
                    break
                }
            }

            if container.ready == false, container.kind == .container {
                signals.append(
                    KubernetesResourceDebugSignal(
                        severity: .warning,
                        title: "\(container.name) is not ready",
                        detail: "Readiness probes, startup work, or dependency checks may still be failing."
                    )
                )
            }

            if let restartCount = container.restartCount, restartCount > 0 {
                let lastState = container.lastState
                let reason = lastState?.reason.map { " Last reason: \($0)." } ?? ""
                let exitCode = lastState?.exitCode.map { " Exit code: \($0)." } ?? ""
                signals.append(
                    KubernetesResourceDebugSignal(
                        severity: restartCount >= 3 ? .critical : .warning,
                        title: "\(container.name) restarted \(restartCount) \(restartCount == 1 ? "time" : "times")",
                        detail: "Check current and previous logs.\(reason)\(exitCode)"
                    )
                )
            }
        }
    }

    nonisolated private static let criticalWaitingReasons: Set<String> = [
        "CrashLoopBackOff",
        "CreateContainerConfigError",
        "CreateContainerError",
        "ErrImagePull",
        "ImagePullBackOff",
        "InvalidImageName",
        "RunContainerError"
    ]

    nonisolated private static func appendConditionSignals(
        _ conditions: [KubernetesConditionSummary],
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        for condition in conditions {
            let status = condition.status.lowercased()
            guard status == "false" || status == "unknown" else {
                continue
            }

            let severity: KubernetesResourceDebugSeverity = criticalConditionReasons.contains(condition.reason ?? "")
                ? .critical
                : .warning
            let reason = condition.reason.map { ": \($0)" } ?? ""
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: severity,
                    title: "\(condition.type) is \(condition.status)\(reason)",
                    detail: condition.message ?? "Open Conditions and Events for the detailed Kubernetes status."
                )
            )
        }
    }

    nonisolated private static let criticalConditionReasons: Set<String> = [
        "BackoffLimitExceeded",
        "Failed",
        "ProgressDeadlineExceeded"
    ]

    nonisolated private static func appendReplicaSignals(
        kind: String,
        spec: KubernetesJSONValue?,
        status: KubernetesJSONValue?,
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        switch kind {
        case "Deployment", "ReplicaSet", "StatefulSet":
            let desired = spec?["replicas"]?.intValue ?? status?["replicas"]?.intValue
            let ready = status?["readyReplicas"]?.intValue ?? status?["availableReplicas"]?.intValue ?? 0
            let unavailable = status?["unavailableReplicas"]?.intValue
            if let desired, desired > ready {
                let unavailableText = unavailable.map { ", \($0) unavailable" } ?? ""
                signals.append(
                    KubernetesResourceDebugSignal(
                        severity: .warning,
                        title: "\(ready)/\(desired) replicas are ready",
                        detail: "The workload has not reached its desired replica count\(unavailableText). Open Related Pods and Events next."
                    )
                )
            }
        case "DaemonSet":
            let desired = status?["desiredNumberScheduled"]?.intValue
            let ready = status?["numberReady"]?.intValue ?? 0
            let unavailable = status?["numberUnavailable"]?.intValue
            if let desired, desired > ready {
                let unavailableText = unavailable.map { ", \($0) unavailable" } ?? ""
                signals.append(
                    KubernetesResourceDebugSignal(
                        severity: .warning,
                        title: "\(ready)/\(desired) daemon pods are ready",
                        detail: "Some nodes do not have a ready pod yet\(unavailableText). Open Related Pods and Events next."
                    )
                )
            }
        default:
            return
        }
    }

    nonisolated private static func appendJobSignals(
        kind: String,
        status: KubernetesJSONValue?,
        signals: inout [KubernetesResourceDebugSignal]
    ) {
        guard kind == "Job" else {
            return
        }

        let failed = status?["failed"]?.intValue ?? 0
        if failed > 0 {
            signals.append(
                KubernetesResourceDebugSignal(
                    severity: .critical,
                    title: "Job has \(failed) failed \(failed == 1 ? "pod" : "pods")",
                    detail: "Open related Pods, Logs, and Events to inspect the failing attempt."
                )
            )
        }
    }

    nonisolated private static func deduplicatedDebugSignals(
        _ signals: [KubernetesResourceDebugSignal]
    ) -> [KubernetesResourceDebugSignal] {
        var seen: Set<String> = []
        return signals.filter { signal in
            seen.insert(signal.id).inserted
        }
    }

    nonisolated private static func debugTitle(
        for severity: KubernetesResourceDebugSeverity,
        kind: String
    ) -> String {
        switch severity {
        case .healthy:
            return "No Obvious \(kind) Problems"
        case .warning:
            return "\(kind) Needs Attention"
        case .critical:
            return "\(kind) Looks Unhealthy"
        }
    }

    nonisolated private static func debugMessage(
        for severity: KubernetesResourceDebugSeverity,
        kind: String,
        signalCount: Int
    ) -> String {
        switch severity {
        case .healthy:
            return "Vibekube did not find failed conditions, blocked containers, replica gaps, or restart signals in this manifest."
        case .warning:
            return signalCount == 1
                ? "One warning signal was found. Start with Events or the targeted detail tab below."
                : "\(signalCount) warning signals were found. Start with Events or the targeted detail tabs below."
        case .critical:
            return signalCount == 1
                ? "One high-priority failure signal was found. Logs, Events, and YAML are the fastest next checks."
                : "\(signalCount) failure signals were found. Logs, Events, and YAML are the fastest next checks."
        }
    }

    nonisolated private static func containerSummaries(
        in containers: [KubernetesJSONValue]?,
        statuses: [KubernetesJSONValue]?,
        kind: KubernetesContainerKind
    ) -> [KubernetesContainerSummary] {
        let statusPairs: [(String, [String: KubernetesJSONValue])] = (statuses ?? []).compactMap { value in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }
            return (name, object)
        }
        let statusByName: [String: [String: KubernetesJSONValue]] = Dictionary(
            statusPairs,
            uniquingKeysWith: { first, _ in first }
        )

        return containers?.compactMap { value -> KubernetesContainerSummary? in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }

            let status = statusByName[name]
            return KubernetesContainerSummary(
                name: name,
                kind: kind,
                image: object["image"]?.stringValue,
                imagePullPolicy: object["imagePullPolicy"]?.stringValue,
                imageID: status?["imageID"]?.stringValue,
                containerID: status?["containerID"]?.stringValue,
                ready: status?["ready"]?.boolValue,
                started: status?["started"]?.boolValue,
                restartCount: status?["restartCount"]?.intValue,
                currentState: containerState(in: status?["state"]),
                lastState: containerState(in: status?["lastState"]),
                resources: containerResources(in: object["resources"]),
                probes: containerProbes(in: object),
                volumeMounts: containerVolumeMounts(in: object["volumeMounts"])
            )
        } ?? []
    }

    nonisolated private static func containerState(in value: KubernetesJSONValue?) -> KubernetesContainerStateSummary? {
        guard let object = value?.objectValue else {
            return nil
        }

        if let waiting = object["waiting"]?.objectValue {
            return KubernetesContainerStateSummary(
                kind: .waiting,
                reason: waiting["reason"]?.stringValue,
                message: waiting["message"]?.stringValue,
                startedAt: nil,
                finishedAt: nil,
                exitCode: nil,
                signal: nil
            )
        }

        if let running = object["running"]?.objectValue {
            return KubernetesContainerStateSummary(
                kind: .running,
                reason: nil,
                message: nil,
                startedAt: running["startedAt"]?.stringValue,
                finishedAt: nil,
                exitCode: nil,
                signal: nil
            )
        }

        if let terminated = object["terminated"]?.objectValue {
            return KubernetesContainerStateSummary(
                kind: .terminated,
                reason: terminated["reason"]?.stringValue,
                message: terminated["message"]?.stringValue,
                startedAt: terminated["startedAt"]?.stringValue,
                finishedAt: terminated["finishedAt"]?.stringValue,
                exitCode: terminated["exitCode"]?.intValue,
                signal: terminated["signal"]?.intValue
            )
        }

        return nil
    }

    nonisolated private static func containerResources(
        in value: KubernetesJSONValue?
    ) -> KubernetesContainerResourcesSummary {
        KubernetesContainerResourcesSummary(
            requests: stringMap(value?["requests"], redactingValues: false, kind: nil),
            limits: stringMap(value?["limits"], redactingValues: false, kind: nil)
        )
    }

    nonisolated private static func containerProbes(
        in object: [String: KubernetesJSONValue]
    ) -> [KubernetesContainerProbeSummary] {
        [
            ("startupProbe", KubernetesContainerProbeKind.startup),
            ("readinessProbe", KubernetesContainerProbeKind.readiness),
            ("livenessProbe", KubernetesContainerProbeKind.liveness)
        ].compactMap { key, kind in
            guard let probeObject = object[key]?.objectValue else {
                return nil
            }

            return KubernetesContainerProbeSummary(
                kind: kind,
                handler: probeHandlerDescription(in: probeObject),
                initialDelaySeconds: probeObject["initialDelaySeconds"]?.intValue,
                periodSeconds: probeObject["periodSeconds"]?.intValue,
                timeoutSeconds: probeObject["timeoutSeconds"]?.intValue,
                successThreshold: probeObject["successThreshold"]?.intValue,
                failureThreshold: probeObject["failureThreshold"]?.intValue
            )
        }
    }

    nonisolated private static func probeHandlerDescription(in object: [String: KubernetesJSONValue]) -> String? {
        if let httpGet = object["httpGet"]?.objectValue {
            let scheme = httpGet["scheme"]?.stringValue ?? "HTTP"
            let path = httpGet["path"]?.stringValue ?? "/"
            let port = httpGet["port"]?.displayValue ?? "-"
            return "\(scheme) \(path) :\(port)"
        }

        if let tcpSocket = object["tcpSocket"]?.objectValue {
            let port = tcpSocket["port"]?.displayValue ?? "-"
            return "TCP :\(port)"
        }

        if let exec = object["exec"]?.objectValue {
            let command = exec["command"]?.arrayValue?
                .map(\.displayValue)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return command.map { "exec \($0)" } ?? "exec"
        }

        if let grpc = object["grpc"]?.objectValue {
            let port = grpc["port"]?.displayValue ?? "-"
            if let service = grpc["service"]?.stringValue, !service.isEmpty {
                return "gRPC \(service) :\(port)"
            }
            return "gRPC :\(port)"
        }

        return nil
    }

    nonisolated private static func containerVolumeMounts(
        in value: KubernetesJSONValue?
    ) -> [KubernetesContainerVolumeMountSummary] {
        value?.arrayValue?.compactMap { value -> KubernetesContainerVolumeMountSummary? in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue,
                  let mountPath = object["mountPath"]?.stringValue else {
                return nil
            }

            return KubernetesContainerVolumeMountSummary(
                name: name,
                mountPath: mountPath,
                subPath: object["subPath"]?.stringValue,
                readOnly: object["readOnly"]?.boolValue ?? false
            )
        } ?? []
    }

    nonisolated private static func environment(in spec: KubernetesJSONValue?) -> [KubernetesContainerEnvironmentSummary] {
        spec?["containers"]?.arrayValue?.compactMap { value -> KubernetesContainerEnvironmentSummary? in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }

            let variables = object["env"]?.arrayValue?.compactMap(environmentVariable) ?? []
            let envFrom = object["envFrom"]?.arrayValue?.compactMap(environmentFromSource) ?? []

            guard !variables.isEmpty || !envFrom.isEmpty else {
                return nil
            }

            return KubernetesContainerEnvironmentSummary(
                containerName: name,
                variables: variables,
                envFrom: envFrom
            )
        } ?? []
    }

    nonisolated private static func environmentVariable(_ value: KubernetesJSONValue) -> KubernetesEnvVarSummary? {
        guard let object = value.objectValue,
              let name = object["name"]?.stringValue else {
            return nil
        }

        return KubernetesEnvVarSummary(
            name: name,
            literalValue: object["value"]?.stringValue,
            source: environmentVariableSource(object["valueFrom"])
        )
    }

    nonisolated private static func environmentVariableSource(_ value: KubernetesJSONValue?) -> KubernetesEnvVarSourceSummary? {
        guard let value else {
            return nil
        }

        if let object = value["secretKeyRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .secretKeyRef,
                name: object["name"]?.stringValue,
                key: object["key"]?.stringValue,
                fieldPath: nil,
                resource: nil,
                isOptional: object["optional"]?.boolValue
            )
        }

        if let object = value["configMapKeyRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .configMapKeyRef,
                name: object["name"]?.stringValue,
                key: object["key"]?.stringValue,
                fieldPath: nil,
                resource: nil,
                isOptional: object["optional"]?.boolValue
            )
        }

        if let object = value["fieldRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .fieldRef,
                name: nil,
                key: nil,
                fieldPath: object["fieldPath"]?.stringValue,
                resource: nil,
                isOptional: nil
            )
        }

        if let object = value["resourceFieldRef"]?.objectValue {
            return KubernetesEnvVarSourceSummary(
                kind: .resourceFieldRef,
                name: object["containerName"]?.stringValue,
                key: nil,
                fieldPath: nil,
                resource: object["resource"]?.stringValue,
                isOptional: nil
            )
        }

        return KubernetesEnvVarSourceSummary(
            kind: .unknown,
            name: nil,
            key: nil,
            fieldPath: nil,
            resource: nil,
            isOptional: nil
        )
    }

    nonisolated private static func environmentFromSource(_ value: KubernetesJSONValue) -> KubernetesEnvFromSummary? {
        guard let object = value.objectValue else {
            return nil
        }

        if let secretRef = object["secretRef"]?.objectValue,
           let name = secretRef["name"]?.stringValue {
            return KubernetesEnvFromSummary(
                kind: .secretRef,
                name: name,
                prefix: object["prefix"]?.stringValue,
                isOptional: secretRef["optional"]?.boolValue
            )
        }

        if let configMapRef = object["configMapRef"]?.objectValue,
           let name = configMapRef["name"]?.stringValue {
            return KubernetesEnvFromSummary(
                kind: .configMapRef,
                name: name,
                prefix: object["prefix"]?.stringValue,
                isOptional: configMapRef["optional"]?.boolValue
            )
        }

        return nil
    }
}

struct KubernetesOwnerReferenceSummary: Decodable, Equatable, Hashable, Identifiable {
    var kind: String
    var name: String
    var controller: Bool

    var id: String {
        "\(kind)/\(name)"
    }
}

struct KubernetesLabelSelectorSummary: Equatable {
    var matchLabels: [String: String]

    var displayText: String {
        matchLabels
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    func matches(labels: [String: String]?) -> Bool {
        guard let labels else {
            return false
        }

        return matchLabels.allSatisfy { key, value in
            labels[key] == value
        }
    }
}

struct KubernetesIngressServiceBackendSummary: Equatable, Hashable, Identifiable {
    var name: String
    var route: String

    var id: String {
        "\(name)/\(route)"
    }
}

struct KubernetesPortForwardTargetSummary: Equatable, Hashable, Identifiable {
    var resourceKind: String
    var resourceName: String
    var namespace: String?
    var portName: String?
    var localPort: Int
    var remotePort: Int
    var protocolName: String?

    var id: String {
        [
            resourceKind,
            namespace ?? "",
            resourceName,
            portName ?? "",
            String(localPort),
            String(remotePort)
        ].joined(separator: "/")
    }

    var displayName: String {
        if let portName, !portName.isEmpty {
            return portName
        }
        return "Port \(remotePort)"
    }

    var displayDetail: String {
        let protocolText = protocolName?.isEmpty == false ? "\(protocolName ?? "TCP") " : ""
        return "\(protocolText)127.0.0.1:\(localPort) -> \(resourceKind)/\(resourceName):\(remotePort)"
    }

    static func resourceKind(forKubernetesKind kind: String) -> String? {
        switch kind {
        case "Pod":
            "pod"
        case "Service":
            "service"
        case "Deployment":
            "deployment"
        default:
            nil
        }
    }

    static func defaultLocalPort(forRemotePort remotePort: Int) -> Int {
        remotePort < 1024 ? 10_000 + remotePort : remotePort
    }
}

struct KubernetesResourceReferenceSummary: Equatable, Hashable, Identifiable {
    var name: String
    var detail: String

    var id: String {
        "\(name)/\(detail)"
    }
}

enum KubernetesReferencedResourceKind {
    case configMap
    case secret
}

struct KubernetesConditionSummary: Equatable, Identifiable {
    var type: String
    var status: String
    var reason: String?
    var message: String?
    var lastTransitionTime: String?

    var id: String {
        "\(type)/\(status)/\(reason ?? "")/\(lastTransitionTime ?? "")"
    }
}

struct KubernetesPodSchedulingSummary: Equatable {
    var nodeName: String?
    var nominatedNodeName: String?
    var qosClass: String?

    var rows: [(String, String)] {
        [
            ("Node", nodeName?.isEmpty == false ? nodeName ?? "-" : "Not assigned"),
            ("Nominated Node", nominatedNodeName?.isEmpty == false ? nominatedNodeName ?? "-" : "-"),
            ("QoS Class", qosClass?.isEmpty == false ? qosClass ?? "-" : "-")
        ]
    }
}

struct KubernetesResourceDebugSummary: Equatable {
    var severity: KubernetesResourceDebugSeverity
    var title: String
    var message: String
    var signals: [KubernetesResourceDebugSignal]
}

struct KubernetesResourceDebugSignal: Equatable, Identifiable {
    var severity: KubernetesResourceDebugSeverity
    var title: String
    var detail: String

    var id: String {
        "\(severity.rawValue)/\(title)/\(detail)"
    }
}

enum KubernetesResourceDebugSeverity: Int, Comparable, Equatable {
    case healthy = 0
    case warning = 1
    case critical = 2

    static func < (
        lhs: KubernetesResourceDebugSeverity,
        rhs: KubernetesResourceDebugSeverity
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct KubernetesContainerSummary: Equatable, Identifiable {
    var name: String
    var kind: KubernetesContainerKind
    var image: String?
    var imagePullPolicy: String?
    var imageID: String?
    var containerID: String?
    var ready: Bool?
    var started: Bool?
    var restartCount: Int?
    var currentState: KubernetesContainerStateSummary?
    var lastState: KubernetesContainerStateSummary?
    var resources: KubernetesContainerResourcesSummary
    var probes: [KubernetesContainerProbeSummary]
    var volumeMounts: [KubernetesContainerVolumeMountSummary]

    var id: String {
        "\(kind.rawValue)/\(name)"
    }
}

enum KubernetesContainerKind: String, Equatable {
    case initContainer
    case container
    case ephemeralContainer

    var title: String {
        switch self {
        case .initContainer:
            "Init"
        case .container:
            "Container"
        case .ephemeralContainer:
            "Ephemeral"
        }
    }
}

struct KubernetesContainerStateSummary: Equatable {
    var kind: KubernetesContainerStateKind
    var reason: String?
    var message: String?
    var startedAt: String?
    var finishedAt: String?
    var exitCode: Int?
    var signal: Int?

    var title: String {
        switch kind {
        case .waiting:
            reason.map { "Waiting: \($0)" } ?? "Waiting"
        case .running:
            "Running"
        case .terminated:
            reason.map { "Terminated: \($0)" } ?? "Terminated"
        }
    }
}

enum KubernetesContainerStateKind: String, Equatable {
    case waiting
    case running
    case terminated
}

struct KubernetesContainerResourcesSummary: Equatable {
    var requests: [String: String]
    var limits: [String: String]

    var isEmpty: Bool {
        requests.isEmpty && limits.isEmpty
    }
}

struct KubernetesContainerProbeSummary: Equatable, Identifiable {
    var kind: KubernetesContainerProbeKind
    var handler: String?
    var initialDelaySeconds: Int?
    var periodSeconds: Int?
    var timeoutSeconds: Int?
    var successThreshold: Int?
    var failureThreshold: Int?

    var id: String {
        kind.rawValue
    }
}

enum KubernetesContainerProbeKind: String, Equatable {
    case startup
    case readiness
    case liveness

    var title: String {
        switch self {
        case .startup:
            "Startup"
        case .readiness:
            "Readiness"
        case .liveness:
            "Liveness"
        }
    }
}

struct KubernetesContainerVolumeMountSummary: Equatable, Identifiable {
    var name: String
    var mountPath: String
    var subPath: String?
    var readOnly: Bool

    var id: String {
        "\(name)|\(mountPath)|\(subPath ?? "")"
    }
}

struct KubernetesContainerEnvironmentSummary: Equatable, Identifiable {
    var containerName: String
    var variables: [KubernetesEnvVarSummary]
    var envFrom: [KubernetesEnvFromSummary]

    var id: String {
        containerName
    }
}

struct KubernetesEnvVarSummary: Equatable, Identifiable {
    var name: String
    var literalValue: String?
    var source: KubernetesEnvVarSourceSummary?

    var id: String {
        [
            name,
            literalValue ?? "",
            source?.id ?? ""
        ].joined(separator: "|")
    }
}

struct KubernetesEnvVarSourceSummary: Equatable {
    var kind: KubernetesEnvVarSourceKind
    var name: String?
    var key: String?
    var fieldPath: String?
    var resource: String?
    var isOptional: Bool?

    var id: String {
        [
            kind.rawValue,
            name ?? "",
            key ?? "",
            fieldPath ?? "",
            resource ?? ""
        ].joined(separator: "|")
    }
}

enum KubernetesEnvVarSourceKind: String, Equatable {
    case secretKeyRef
    case configMapKeyRef
    case fieldRef
    case resourceFieldRef
    case unknown
}

struct KubernetesEnvFromSummary: Equatable, Identifiable {
    var kind: KubernetesEnvFromSourceKind
    var name: String
    var prefix: String?
    var isOptional: Bool?

    var id: String {
        [
            kind.rawValue,
            name,
            prefix ?? ""
        ].joined(separator: "|")
    }
}

enum KubernetesEnvFromSourceKind: String, Equatable {
    case secretRef
    case configMapRef
}

enum KubernetesYAMLRenderer {
    static func render(
        _ value: KubernetesJSONValue,
        redactedTopLevelKeys: Set<String> = []
    ) -> String {
        renderLines(
            value,
            indent: 0,
            path: [],
            redactedTopLevelKeys: redactedTopLevelKeys
        )
        .joined(separator: "\n") + "\n"
    }

    private static func renderLines(
        _ value: KubernetesJSONValue,
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        switch value {
        case .object(let object):
            return renderObject(
                object,
                indent: indent,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        case .array(let array):
            return renderArray(
                array,
                indent: indent,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        case .string, .number, .bool, .null:
            return ["\(indentation(indent))\(scalar(value))"]
        }
    }

    private static func renderObject(
        _ object: [String: KubernetesJSONValue],
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        guard !object.isEmpty else {
            return ["\(indentation(indent)){}"]
        }

        var lines: [String] = []
        for key in orderedKeys(for: object) {
            guard let value = object[key] else {
                continue
            }

            let keyText = escapedKey(key)
            if path.isEmpty, redactedTopLevelKeys.contains(key) {
                lines.append("\(indentation(indent))\(keyText): <redacted>")
                continue
            }

            if isScalar(value) {
                lines.append("\(indentation(indent))\(keyText): \(scalar(value))")
            } else {
                lines.append("\(indentation(indent))\(keyText):")
                lines += renderLines(
                    value,
                    indent: indent + 2,
                    path: path + [key],
                    redactedTopLevelKeys: redactedTopLevelKeys
                )
            }
        }

        return lines
    }

    private static func renderArray(
        _ array: [KubernetesJSONValue],
        indent: Int,
        path: [String],
        redactedTopLevelKeys: Set<String>
    ) -> [String] {
        guard !array.isEmpty else {
            return ["\(indentation(indent))[]"]
        }

        return array.flatMap { value -> [String] in
            if isScalar(value) {
                return ["\(indentation(indent))- \(scalar(value))"]
            }

            return ["\(indentation(indent))-"] + renderLines(
                value,
                indent: indent + 2,
                path: path,
                redactedTopLevelKeys: redactedTopLevelKeys
            )
        }
    }

    private static func orderedKeys(for object: [String: KubernetesJSONValue]) -> [String] {
        let preferred = [
            "apiVersion",
            "kind",
            "metadata",
            "spec",
            "status",
            "data",
            "stringData",
            "binaryData"
        ]
        let preferredKeys = preferred.filter { object[$0] != nil }
        let remainingKeys = object.keys
            .filter { !preferred.contains($0) }
            .sorted { lhs, rhs in lhs.localizedStandardCompare(rhs) == .orderedAscending }
        return preferredKeys + remainingKeys
    }

    private static func isScalar(_ value: KubernetesJSONValue) -> Bool {
        switch value {
        case .string, .number, .bool, .null:
            true
        case .object, .array:
            false
        }
    }

    private static func scalar(_ value: KubernetesJSONValue) -> String {
        switch value {
        case .string(let value):
            yamlString(value)
        case .number(let value):
            if value.rounded() == value {
                String(Int(value))
            } else {
                String(value)
            }
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "null"
        case .object, .array:
            ""
        }
    }

    private static func yamlString(_ value: String) -> String {
        guard !value.isEmpty else {
            return "\"\""
        }

        let reserved = ["false", "null", "true", "~"]
        let simplePattern = #"^[A-Za-z0-9_./:@-]+$"#
        let isSimple = value.range(of: simplePattern, options: .regularExpression) != nil
        if isSimple, !reserved.contains(value.lowercased()) {
            return value
        }

        return "\"\(value.map(escapedCharacter).joined())\""
    }

    private static func escapedKey(_ key: String) -> String {
        yamlString(key)
    }

    nonisolated private static func escapedCharacter(_ character: Character) -> String {
        switch character {
        case "\\":
            "\\\\"
        case "\"":
            "\\\""
        case "\n":
            "\\n"
        case "\r":
            "\\r"
        case "\t":
            "\\t"
        default:
            String(character)
        }
    }

    private static func indentation(_ width: Int) -> String {
        String(repeating: " ", count: width)
    }
}
