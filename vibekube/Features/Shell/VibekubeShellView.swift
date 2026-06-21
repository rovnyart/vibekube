import AppKit
import SwiftUI

struct VibekubeShellView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var focusedField: ShellFocusedField?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ClusterSidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            ResourceSidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detailView
                .navigationTitle(appModel.route.title)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ClusterPicker()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                NamespacePicker()

                TextField("Search", text: $appModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .focused($focusedField, equals: .search)
                    .accessibilityIdentifier("toolbar.search")

                PortForwardSessionsButton()

                Button {
                    appModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh")
                .accessibilityIdentifier("toolbar.refresh")

                Button {
                    appModel.selectResource(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("toolbar.settings")
            }
        }
        .onChange(of: appModel.searchFocusRequestID) {
            focusedField = .search
        }
        .accessibilityIdentifier("vibekube.shell")
    }

    @ViewBuilder
    private var detailView: some View {
        switch appModel.selectedResource ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .settings:
            SettingsView()
        case .aiAssistant:
            AIOverviewView()
        case .customResources:
            ResourceCatalogView()
        case let resource where resource.discoveredResource(in: appModel.selectedDiscovery) != nil:
            ResourceListView(item: resource)
                .id(resource.id)
        default:
            ResourcePlaceholderView(item: appModel.selectedResource ?? .dashboard)
        }
    }
}

private enum ShellFocusedField {
    case search
}

private enum NamespacePickerFocusedField {
    case search
}

private struct PortForwardSessionsButton: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isPresented = false

    var body: some View {
        if !appModel.portForwardSessions.isEmpty {
            Button {
                isPresented.toggle()
            } label: {
                Label(buttonTitle, systemImage: "arrow.left.and.right")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                PortForwardSessionsPopover()
                    .environmentObject(appModel)
            }
            .help(buttonTitle)
            .accessibilityIdentifier("toolbar.portForwardSessions")
        }
    }

    private var buttonTitle: String {
        let activeCount = appModel.portForwardSessions.filter(\.isActive).count
        guard activeCount > 0 else {
            return "Port Forwards"
        }
        return activeCount == 1 ? "1 Port Forward" : "\(activeCount) Port Forwards"
    }
}

private struct PortForwardSessionsPopover: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Port Forwards")
                    .font(.headline)

                Spacer()

                if appModel.portForwardSessions.contains(where: { !$0.isActive }) {
                    Button("Clear Finished") {
                        appModel.clearInactivePortForwardSessions()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(appModel.portForwardSessions) { session in
                        PortForwardSessionRow(session: session)

                        if session.id != appModel.portForwardSessions.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(width: 440, height: min(320, CGFloat(max(appModel.portForwardSessions.count, 1)) * 76))
        }
        .frame(width: 440)
    }
}

private struct PortForwardSessionRow: View {
    @EnvironmentObject private var appModel: AppModel

    let session: PortForwardSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusImage)
                .foregroundStyle(statusTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayResource)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(session.displayNamespace)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if case .running = session.status {
                Button {
                    openURL(session.localURLString)
                } label: {
                    Label("Open", systemImage: "safari")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open \(session.localURLString)")

                Button {
                    copyToPasteboard(session.localURLString)
                } label: {
                    Label("Copy URL", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Copy \(session.localURLString)")
            }

            if session.isActive {
                Button {
                    appModel.stopPortForward(sessionID: session.id)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Stop")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var detailText: String {
        switch session.status {
        case .starting:
            "\(session.localURLString) -> \(session.remotePort) starting"
        case .running:
            "\(session.localURLString) -> \(session.remotePort) running"
        case .stopped:
            "\(session.localURLString) stopped"
        case .failed(let message):
            message
        }
    }

    private var statusImage: String {
        switch session.status {
        case .starting:
            "hourglass"
        case .running:
            "checkmark.circle.fill"
        case .stopped:
            "stop.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch session.status {
        case .starting:
            .orange
        case .running:
            .green
        case .stopped:
            .secondary
        case .failed:
            .red
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct ClusterPicker: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Cluster", selection: clusterSelection) {
                ForEach(appModel.clusters) { cluster in
                    Text(cluster.name)
                        .tag(cluster.id as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            StatusBadge(state: appModel.selectedConnectionState)

            Button {
                if appModel.selectedConnectionState == .connected ||
                    appModel.selectedConnectionState == .connecting ||
                    appModel.selectedConnectionState == .authenticating {
                    appModel.disconnectSelectedCluster()
                } else {
                    appModel.connectSelectedCluster()
                }
            } label: {
                Label(connectButtonTitle, systemImage: connectButtonImage)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .disabled(!canUseConnectionButton)
            .help(connectButtonTitle)
            .accessibilityIdentifier("toolbar.connection")
        }
    }

    private var connectButtonTitle: String {
        switch appModel.selectedConnectionState {
        case .connected:
            "Disconnect"
        case .connecting, .authenticating:
            "Cancel Connection"
        default:
            "Connect"
        }
    }

    private var connectButtonImage: String {
        switch appModel.selectedConnectionState {
        case .connected:
            "xmark.circle"
        case .connecting, .authenticating:
            "stop.circle"
        default:
            "bolt.horizontal.circle"
        }
    }

    private var canUseConnectionButton: Bool {
        appModel.selectedConnectionState == .connected ||
            appModel.selectedConnectionState == .connecting ||
            appModel.selectedConnectionState == .authenticating ||
            appModel.canConnectSelectedCluster
    }

    private var clusterSelection: Binding<ClusterSummary.ID?> {
        Binding(
            get: { appModel.selectedClusterID },
            set: { id in
                DispatchQueue.main.async {
                    appModel.selectCluster(id: id)
                }
            }
        )
    }
}

private struct NamespacePicker: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isPresented = false
    @State private var searchText = ""
    @FocusState private var focusedField: NamespacePickerFocusedField?

    var body: some View {
        if appModel.selectedConnectionState == .connected {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(appModel.selectedNamespaceTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 190, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                namespacePopover
            }
            .help(appModel.namespaceAccessErrorMessage ?? "Namespace scope")
            .accessibilityIdentifier("toolbar.namespace")
        }
    }

    private var namespacePopover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search namespaces", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .search)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider()

            if filteredNamespaces.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No namespaces match")
                        .font(.headline)
                    Text(searchText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredNamespaces, id: \.self) { namespace in
                            namespaceRow(namespace)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }

            if let error = appModel.namespaceAccessErrorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 360)
        .onAppear {
            searchText = ""
            focusedField = .search
        }
    }

    private func namespaceRow(_ namespace: String) -> some View {
        Button {
            appModel.selectNamespace(namespace)
            isPresented = false
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .frame(width: 14)
                    .foregroundStyle(.blue)
                    .opacity(namespace == appModel.selectedNamespaceSelection ? 1 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appModel.namespaceTitle(for: namespace))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if namespace == AppModel.allNamespacesSelection {
                        Text("Cluster scope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .background {
            if namespace == appModel.selectedNamespaceSelection {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .accessibilityIdentifier("namespace.option.\(namespace)")
    }

    private var filteredNamespaces: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return appModel.namespaceSelectionOptions
        }

        return appModel.namespaceSelectionOptions.filter { namespace in
            appModel.namespaceTitle(for: namespace)
                .localizedStandardContains(query)
        }
    }
}
