import SwiftUI

struct VibekubeCommands: Commands {
    @ObservedObject var appModel: AppModel

    var body: some Commands {
        CommandMenu("Cluster") {
            Button("Connect") {
                appModel.connectSelectedCluster()
            }
            .disabled(!appModel.canConnectSelectedCluster)

            Button("Disconnect") {
                appModel.disconnectSelectedCluster()
            }
            .disabled(appModel.selectedConnectionState != .connected)

            Divider()

            Button("Refresh") {
                appModel.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Navigate") {
            Button("Dashboard") {
                appModel.selectResource(.dashboard)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Pods") {
                appModel.selectResource(.pods)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Logs") {
                appModel.selectResource(.logs)
            }
            .keyboardShortcut("3", modifiers: [.command])
        }
    }
}
