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
        case .logs:
            LogsView()
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
                    appModel.selectedConnectionState == .connecting {
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
        case .connecting:
            "Cancel Connection"
        default:
            "Connect"
        }
    }

    private var connectButtonImage: String {
        switch appModel.selectedConnectionState {
        case .connected:
            "xmark.circle"
        case .connecting:
            "stop.circle"
        default:
            "bolt.horizontal.circle"
        }
    }

    private var canUseConnectionButton: Bool {
        appModel.selectedConnectionState == .connected ||
            appModel.selectedConnectionState == .connecting ||
            appModel.canConnectSelectedCluster
    }

    private var clusterSelection: Binding<ClusterSummary.ID?> {
        Binding(
            get: { appModel.selectedClusterID },
            set: { appModel.selectCluster(id: $0) }
        )
    }
}

private struct NamespacePicker: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        if appModel.selectedConnectionState == .connected {
            Picker("Namespace", selection: namespaceSelection) {
                ForEach(appModel.namespaceSelectionOptions, id: \.self) { namespace in
                    Text(appModel.namespaceTitle(for: namespace))
                        .tag(namespace)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
            .help(appModel.namespaceAccessErrorMessage ?? "Namespace scope")
            .accessibilityIdentifier("toolbar.namespace")
        }
    }

    private var namespaceSelection: Binding<String> {
        Binding(
            get: { appModel.selectedNamespaceSelection },
            set: { appModel.selectNamespace($0) }
        )
    }
}
