import AppKit
import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPodID: KubernetesUnstructuredResource.ID?
    @State private var selectedContainerName = ""

    var body: some View {
        HSplitView {
            podListPane
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)

            logPane
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: appModel.resourceListTaskID(for: .pods)) {
            appModel.loadResourceList(for: .pods)
        }
        .accessibilityIdentifier("logs.view")
    }

    @ViewBuilder
    private var podListPane: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Pods", systemImage: "shippingbox")
                    .font(.headline)

                Spacer()

                Button {
                    appModel.loadResourceList(for: .pods, force: true)
                } label: {
                    Label("Refresh Pods", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Refresh Pods")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            switch appModel.resourceListState(for: .pods) {
            case .idle:
                EmptyStateView(
                    title: "No Pods Loaded",
                    subtitle: appModel.selectedConnectionState == .connected ? "Refresh to load Pods." : "Connect to a cluster first.",
                    systemImage: "shippingbox"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loading(let progress):
                ResourceListLoadingView(
                    title: "Loading Pods",
                    progress: progress,
                    cancel: {
                        appModel.cancelResourceList(for: .pods)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                VStack(spacing: 12) {
                    EmptyStateView(
                        title: "Could Not Load Pods",
                        subtitle: message,
                        systemImage: "exclamationmark.triangle"
                    )

                    Button {
                        appModel.loadResourceList(for: .pods, force: true)
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let snapshot):
                podList(snapshot)
            }
        }
    }

    private func podList(_ snapshot: ResourceListSnapshot) -> some View {
        let pods = filteredPods(snapshot)

        return Group {
            if pods.isEmpty {
                EmptyStateView(
                    title: "No Pods",
                    subtitle: "No Pods are available in the current namespace scope.",
                    systemImage: "shippingbox"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedPodID) {
                    ForEach(pods) { pod in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pod.displayName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(pod.displayNamespace)
                                Text(pod.displayStatus)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                        .padding(.vertical, 3)
                        .tag(pod.id)
                    }
                }
                .onAppear {
                    reconcileSelection(with: pods)
                }
                .onChange(of: pods.map(\.id)) {
                    reconcileSelection(with: pods)
                }
                .onChange(of: selectedPodID) {
                    reconcileContainer(with: selectedPod(in: pods))
                }
            }
        }
    }

    @ViewBuilder
    private var logPane: some View {
        switch appModel.resourceListState(for: .pods) {
        case .loaded(let snapshot):
            let pods = filteredPods(snapshot)
            if let pod = selectedPod(in: pods) {
                selectedLogPane(pod)
            } else {
                EmptyStateView(
                    title: "Select a Pod",
                    subtitle: "Choose a Pod to load its recent logs.",
                    systemImage: "terminal"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            EmptyStateView(
                title: "Logs",
                subtitle: "Load Pods before selecting a log target.",
                systemImage: "terminal"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func selectedLogPane(_ pod: KubernetesUnstructuredResource) -> some View {
        let container = selectedContainerName.isEmpty ? nil : selectedContainerName
        let state = appModel.podLogState(for: pod, containerName: container)

        return VStack(spacing: 0) {
            logHeader(pod: pod)

            Divider()

            logContent(state)
        }
        .task(id: appModel.podLogTaskID(for: pod, containerName: container)) {
            appModel.loadPodLogs(for: pod, containerName: container)
        }
    }

    private func logHeader(pod: KubernetesUnstructuredResource) -> some View {
        let containers = pod.containerNames

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pod.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                Text("\(pod.displayNamespace) - tail 200 lines")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if containers.count > 1 {
                Picker("Container", selection: $selectedContainerName) {
                    ForEach(containers, id: \.self) { container in
                        Text(container).tag(container)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }

            Button {
                appModel.loadPodLogs(
                    for: pod,
                    containerName: selectedContainerName.isEmpty ? nil : selectedContainerName,
                    force: true
                )
            } label: {
                Label("Refresh Logs", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("Refresh Logs")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
        .onAppear {
            reconcileContainer(with: pod)
        }
    }

    @ViewBuilder
    private func logContent(_ state: PodLogLoadState) -> some View {
        switch state {
        case .idle:
            ProgressView("Loading Logs")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView("Loading Logs")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyStateView(
                title: "Could Not Load Logs",
                subtitle: message,
                systemImage: "exclamationmark.triangle"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let snapshot):
            VStack(spacing: 0) {
                HStack {
                    Text("Loaded \(snapshot.loadedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(snapshot.text, forType: .string)
                    } label: {
                        Label("Copy Logs", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Logs")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .textBackgroundColor))

                Divider()

                ScrollView {
                    Text(snapshot.text.isEmpty ? "No log lines returned." : snapshot.text)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func filteredPods(_ snapshot: ResourceListSnapshot) -> [KubernetesUnstructuredResource] {
        let searchText = appModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pods = snapshot.items.filter { $0.displayKind == "Pod" }
        let filteredPods = searchText.isEmpty
            ? pods
            : pods.filter { $0.searchBlob.contains(searchText) }

        return filteredPods.sorted {
            if $0.displayNamespace == $1.displayNamespace {
                return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            return $0.displayNamespace.localizedStandardCompare($1.displayNamespace) == .orderedAscending
        }
    }

    private func selectedPod(in pods: [KubernetesUnstructuredResource]) -> KubernetesUnstructuredResource? {
        guard let selectedPodID else {
            return pods.first
        }

        return pods.first { $0.id == selectedPodID } ?? pods.first
    }

    private func reconcileSelection(with pods: [KubernetesUnstructuredResource]) {
        guard !pods.isEmpty else {
            selectedPodID = nil
            selectedContainerName = ""
            return
        }

        if let selectedPodID,
           pods.contains(where: { $0.id == selectedPodID }) {
            return
        }

        selectedPodID = pods.first?.id
        reconcileContainer(with: pods.first)
    }

    private func reconcileContainer(with pod: KubernetesUnstructuredResource?) {
        guard let pod else {
            selectedContainerName = ""
            return
        }

        let containers = pod.containerNames
        if containers.contains(selectedContainerName) {
            return
        }

        selectedContainerName = containers.first ?? ""
    }
}

private extension KubernetesUnstructuredResource {
    var containerNames: [String] {
        spec?["containers"]?.arrayValue?.compactMap { value in
            value["name"]?.stringValue
        } ?? []
    }
}
