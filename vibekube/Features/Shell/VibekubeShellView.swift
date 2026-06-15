import SwiftUI

struct VibekubeShellView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ClusterSidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            ResourceSidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            detailView
                .navigationTitle(appModel.selectedResource?.title ?? "Dashboard")
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                ClusterPicker()
            }

            ToolbarItemGroup(placement: .primaryAction) {
                TextField("Search", text: $appModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .accessibilityIdentifier("toolbar.search")

                Button {
                    appModel.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("toolbar.refresh")

                Button {
                    appModel.selectResource(.settings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("toolbar.settings")
            }
        }
        .accessibilityIdentifier("vibekube.shell")
    }

    @ViewBuilder
    private var detailView: some View {
        switch appModel.selectedResource ?? .dashboard {
        case .dashboard:
            DashboardView()
        case .logs:
            LogsPlaceholderView()
        default:
            ResourcePlaceholderView(item: appModel.selectedResource ?? .dashboard)
        }
    }
}

private struct ClusterPicker: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Picker("Cluster", selection: $appModel.selectedClusterID) {
                ForEach(appModel.clusters) { cluster in
                    Text(cluster.name)
                        .tag(cluster.id as String?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)
            .onChange(of: appModel.selectedClusterID) { _, selectedClusterID in
                appModel.selectCluster(id: selectedClusterID)
            }

            StatusBadge(state: appModel.selectedConnectionState)
        }
    }
}
