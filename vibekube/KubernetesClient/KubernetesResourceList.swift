import Foundation

struct KubernetesUnstructuredResourceList: Decodable, Equatable {
    var apiVersion: String?
    var kind: String?
    var metadata: KubernetesListMetadata?
    var items: [KubernetesUnstructuredResource]

    static func merged(_ lists: [KubernetesUnstructuredResourceList]) -> KubernetesUnstructuredResourceList {
        KubernetesUnstructuredResourceList(
            apiVersion: lists.last?.apiVersion ?? lists.first?.apiVersion,
            kind: lists.last?.kind ?? lists.first?.kind,
            metadata: lists.last?.metadata,
            items: lists.flatMap(\.items)
        )
    }
}

struct KubernetesListMetadata: Decodable, Equatable {
    var resourceVersion: String?
    var continueToken: String?
    var remainingItemCount: Int?

    private enum CodingKeys: String, CodingKey {
        case resourceVersion
        case continueToken = "continue"
        case remainingItemCount
    }
}

struct KubernetesUnstructuredResource: Decodable, Identifiable, Equatable, Hashable {
    var apiVersion: String?
    var kind: String?
    var metadata: KubernetesObjectMetadata
    var spec: KubernetesJSONValue?
    var status: KubernetesJSONValue?
    var reason: String?
    var type: String?
    var message: String?
    var note: String?
    var count: Int?
    var eventTime: String?
    var firstTimestamp: String?
    var lastTimestamp: String?
    var deprecatedFirstTimestamp: String?
    var deprecatedLastTimestamp: String?
    var deprecatedCount: Int?
    var reportingComponent: String?
    var reportingController: String?
    var reportingInstance: String?
    var source: KubernetesJSONValue?
    var deprecatedSource: KubernetesJSONValue?
    var regarding: KubernetesJSONValue?
    var involvedObject: KubernetesJSONValue?
    var series: KubernetesJSONValue?

    var id: String {
        metadata.uid ?? "\(displayKind)/\(displayNamespace)/\(displayName)"
    }

    var displayName: String {
        metadata.name ?? "Unknown"
    }

    var displayNamespace: String {
        metadata.namespace ?? "-"
    }

    var displayKind: String {
        kind ?? "Unknown"
    }

    var displayStatus: String {
        if isEvent {
            if let type, let reason {
                return "\(type) \(reason)"
            }
            return reason ?? type ?? "-"
        }

        if let deletionTimestamp = metadata.deletionTimestamp, !deletionTimestamp.isEmpty {
            return "Terminating"
        }

        if let podStatus = podDisplayStatus {
            return podStatus
        }

        if let jobStatus = jobDisplayStatus {
            return jobStatus
        }

        if let phase = status?["phase"]?.stringValue, !phase.isEmpty {
            return phase
        }

        if let ready = readyReplicas, let desired = desiredReplicas {
            return "\(ready)/\(desired) ready"
        }

        if let ready = readyReplicas {
            return "\(ready) ready"
        }

        return type ?? "-"
    }

    var podRestartCount: Int {
        guard isPod else {
            return 0
        }

        return podContainerStatuses.reduce(0) { result, status in
            result + (status["restartCount"]?.intValue ?? 0)
        }
    }

    var podRestartCountDescription: String {
        guard isPod else {
            return "-"
        }

        return String(podRestartCount)
    }

    var podReadyCount: Int {
        guard isPod else {
            return 0
        }

        return podRegularContainerStatuses.filter { status in
            status["ready"]?.boolValue == true
        }.count
    }

    var podContainerCount: Int {
        guard isPod else {
            return 0
        }

        if !podRegularContainerStatuses.isEmpty {
            return podRegularContainerStatuses.count
        }

        return spec?["containers"]?.arrayValue?.count ?? 0
    }

    var podReadySortValue: Int {
        podReadyCount * 1_000 + podContainerCount
    }

    var podReadyDescription: String {
        guard isPod, podContainerCount > 0 else {
            return "-"
        }

        return "\(podReadyCount)/\(podContainerCount)"
    }

    var isPodUnhealthy: Bool {
        guard isPod else {
            return false
        }

        let status = displayStatus.lowercased()
        if status.contains("backoff") ||
            status.contains("error") ||
            status.contains("failed") ||
            status.contains("errimagepull") ||
            status.contains("crashloop") ||
            status.contains("invalidimage") ||
            status.contains("createcontainer") {
            return true
        }

        return false
    }

    var jobSucceededCount: Int {
        guard isJob else {
            return 0
        }

        return status?["succeeded"]?.intValue ?? 0
    }

    var jobCompletionTarget: Int {
        guard isJob else {
            return 0
        }

        return spec?["completions"]?.intValue ?? 1
    }

    var jobCompletionSortValue: Int {
        jobSucceededCount * 1_000 + jobCompletionTarget
    }

    var jobCompletionDescription: String {
        guard isJob else {
            return "-"
        }

        return "\(jobSucceededCount)/\(jobCompletionTarget)"
    }

    var jobFailedCount: Int {
        guard isJob else {
            return 0
        }

        return status?["failed"]?.intValue ?? 0
    }

    var jobFailedDescription: String {
        guard isJob else {
            return "-"
        }

        return String(jobFailedCount)
    }

    var isJobUnhealthy: Bool {
        guard isJob else {
            return false
        }

        let status = displayStatus.lowercased()
        return status.contains("failed") || status.contains("failing") || jobFailedCount > 0 && jobSucceededCount < jobCompletionTarget
    }

    var labelsSummary: String {
        guard let labels = metadata.labels, !labels.isEmpty else {
            return "-"
        }

        return labels
            .sorted { lhs, rhs in lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending }
            .prefix(3)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    var searchBlob: String {
        [
            displayName,
            displayNamespace,
            displayKind,
            displayStatus,
            labelsSummary,
            reason,
            type,
            eventMessage,
            eventSourceDescription,
            eventInvolvedObjectDescription
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    func ageDescription(now: Date = Date()) -> String {
        guard let creationDate else {
            return "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(creationDate)))
        switch seconds {
        case ..<60:
            return "\(seconds)s"
        case ..<3_600:
            return "\(seconds / 60)m"
        case ..<86_400:
            return "\(seconds / 3_600)h"
        default:
            return "\(seconds / 86_400)d"
        }
    }

    var creationDate: Date? {
        guard let creationTimestamp = metadata.creationTimestamp else {
            return nil
        }

        return Self.iso8601Date(from: creationTimestamp)
    }

    var eventMessage: String? {
        note ?? message
    }

    var eventCount: Int? {
        series?["count"]?.intValue ?? deprecatedCount ?? count
    }

    var eventLastObservedDate: Date? {
        [
            series?["lastObservedTime"]?.stringValue,
            deprecatedLastTimestamp,
            lastTimestamp,
            eventTime,
            metadata.creationTimestamp
        ]
        .compactMap { $0 }
        .compactMap(Self.iso8601Date(from:))
        .first
    }

    var eventSourceDescription: String? {
        let controller = reportingController ??
            reportingComponent ??
            source?["component"]?.stringValue ??
            deprecatedSource?["component"]?.stringValue
        let instance = reportingInstance ??
            source?["host"]?.stringValue ??
            deprecatedSource?["host"]?.stringValue

        switch (controller, instance) {
        case (.some(let controller), .some(let instance)) where !instance.isEmpty:
            return "\(controller) / \(instance)"
        case (.some(let controller), _):
            return controller
        case (_, .some(let instance)) where !instance.isEmpty:
            return instance
        default:
            return nil
        }
    }

    var eventInvolvedObjectDescription: String? {
        let object = regarding ?? involvedObject
        let parts = [
            object?["kind"]?.stringValue,
            object?["namespace"]?.stringValue,
            object?["name"]?.stringValue
        ]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else {
                return nil
            }
            return value
        }

        let objectText = parts.joined(separator: " / ")
        if let fieldPath = object?["fieldPath"]?.stringValue, !fieldPath.isEmpty {
            return objectText.isEmpty ? fieldPath : "\(objectText) / \(fieldPath)"
        }

        return objectText.isEmpty ? nil : objectText
    }

    func eventAgeDescription(now: Date = Date()) -> String {
        guard let eventLastObservedDate else {
            return "-"
        }

        let seconds = max(0, Int(now.timeIntervalSince(eventLastObservedDate)))
        switch seconds {
        case ..<60:
            return "\(seconds)s ago"
        case ..<3_600:
            return "\(seconds / 60)m ago"
        case ..<86_400:
            return "\(seconds / 3_600)h ago"
        default:
            return "\(seconds / 86_400)d ago"
        }
    }

    private static func iso8601Date(from string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private var isEvent: Bool {
        displayKind == "Event" || reason != nil && (message != nil || note != nil)
    }

    private var isPod: Bool {
        displayKind == "Pod"
    }

    private var isJob: Bool {
        displayKind == "Job"
    }

    private var podDisplayStatus: String? {
        guard isPod else {
            return nil
        }

        if let initStatus = podContainerStatusText(
            statuses: status?["initContainerStatuses"]?.arrayValue,
            prefix: "Init"
        ) {
            return initStatus
        }

        if let containerStatus = podContainerStatusText(statuses: status?["containerStatuses"]?.arrayValue) {
            return containerStatus
        }

        return nil
    }

    private var jobDisplayStatus: String? {
        guard isJob else {
            return nil
        }

        if jobConditionIsTrue("Failed") {
            return jobConditionReason("Failed") ?? "Failed"
        }

        if jobConditionIsTrue("Complete") {
            return "Complete"
        }

        if let active = status?["active"]?.intValue, active > 0 {
            return "Running"
        }

        if jobFailedCount > 0 {
            return "Failing"
        }

        if jobSucceededCount >= jobCompletionTarget, jobCompletionTarget > 0 {
            return "Complete"
        }

        return "Pending"
    }

    private func jobConditionIsTrue(_ type: String) -> Bool {
        jobCondition(type)?["status"]?.stringValue == "True"
    }

    private func jobConditionReason(_ type: String) -> String? {
        guard let reason = jobCondition(type)?["reason"]?.stringValue,
              !reason.isEmpty else {
            return nil
        }

        return reason
    }

    private func jobCondition(_ type: String) -> [String: KubernetesJSONValue]? {
        status?["conditions"]?.arrayValue?
            .compactMap(\.objectValue)
            .first { condition in
                condition["type"]?.stringValue == type
            }
    }

    private var podContainerStatuses: [[String: KubernetesJSONValue]] {
        [
            status?["initContainerStatuses"]?.arrayValue,
            status?["containerStatuses"]?.arrayValue,
            status?["ephemeralContainerStatuses"]?.arrayValue
        ]
        .compactMap { $0 }
        .flatMap { statuses in
            statuses.compactMap(\.objectValue)
        }
    }

    private var podRegularContainerStatuses: [[String: KubernetesJSONValue]] {
        status?["containerStatuses"]?.arrayValue?.compactMap(\.objectValue) ?? []
    }

    private func podContainerStatusText(
        statuses: [KubernetesJSONValue]?,
        prefix: String? = nil
    ) -> String? {
        let statusObjects = statuses?.compactMap(\.objectValue) ?? []
        for status in statusObjects {
            if let waiting = status["state"]?["waiting"]?.objectValue,
               let reason = waiting["reason"]?.stringValue,
               !reason.isEmpty {
                return prefix.map { "\($0):\(reason)" } ?? reason
            }

            if let terminated = status["state"]?["terminated"]?.objectValue,
               let reason = terminated["reason"]?.stringValue,
               !reason.isEmpty,
               terminated["exitCode"]?.intValue != 0 {
                return prefix.map { "\($0):\(reason)" } ?? reason
            }
        }

        return nil
    }

    private var desiredReplicas: Int? {
        spec?["replicas"]?.intValue ??
            status?["desiredNumberScheduled"]?.intValue ??
            status?["replicas"]?.intValue
    }

    private var readyReplicas: Int? {
        status?["readyReplicas"]?.intValue ??
            status?["availableReplicas"]?.intValue ??
            status?["numberReady"]?.intValue
    }
}

enum KubernetesJSONValue: Decodable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: KubernetesJSONValue])
    case array([KubernetesJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .number(Double(int))
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let object = try? container.decode([String: KubernetesJSONValue].self) {
            self = .object(object)
        } else if let array = try? container.decode([KubernetesJSONValue].self) {
            self = .array(array)
        } else {
            self = .null
        }
    }

    subscript(key: String) -> KubernetesJSONValue? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }

    var stringValue: String? {
        if case .string(let value) = self {
            return value
        }
        return nil
    }

    var intValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value)
        default:
            return nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            value
        case .string(let value):
            Bool(value)
        default:
            nil
        }
    }

    var objectValue: [String: KubernetesJSONValue]? {
        if case .object(let value) = self {
            return value
        }
        return nil
    }

    var arrayValue: [KubernetesJSONValue]? {
        if case .array(let value) = self {
            return value
        }
        return nil
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            value
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
            "-"
        }
    }
}
