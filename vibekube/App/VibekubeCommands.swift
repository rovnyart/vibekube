import AppKit
import SwiftUI

struct VibekubeCommands: Commands {
    @ObservedObject var appModel: AppModel
    @FocusedValue(\.resourceDetailCommandContext) private var resourceDetailCommandContext

    var body: some Commands {
        CommandMenu("Cluster") {
            Button("Connect") {
                appModel.connectSelectedCluster()
            }
            .disabled(!appModel.canConnectSelectedCluster)

            Button("Disconnect") {
                appModel.disconnectSelectedCluster()
            }
            .disabled(appModel.selectedConnectionState != .connected && appModel.selectedConnectionState != .connecting)

            Divider()

            Button("Refresh") {
                appModel.refresh()
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()

            Button("Copy Cluster Identity") {
                copyToPasteboard(appModel.selectedClusterIdentityText)
            }
            .disabled(appModel.selectedClusterIdentityText == nil)
        }

        CommandMenu("Navigate") {
            Button("Search Resources") {
                appModel.focusSearchField()
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Clear Search") {
                appModel.clearSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(appModel.searchText.isEmpty)

            Divider()

            Button("Dashboard") {
                appModel.selectResource(.dashboard)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Pods") {
                appModel.selectResource(.pods)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Deployments") {
                appModel.selectResource(.deployments)
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button("Services") {
                appModel.selectResource(.services)
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button("ConfigMaps") {
                appModel.selectResource(.configMaps)
            }
            .keyboardShortcut("5", modifiers: [.command])

            Button("Secrets") {
                appModel.selectResource(.secrets)
            }
            .keyboardShortcut("6", modifiers: [.command])

            Button("Nodes") {
                appModel.selectResource(.nodes)
            }
            .keyboardShortcut("7", modifiers: [.command])

            Button("Events") {
                appModel.selectResource(.events)
            }
            .keyboardShortcut("8", modifiers: [.command])

            Button("Custom Resources") {
                appModel.selectResource(.customResources)
            }
            .keyboardShortcut("9", modifiers: [.command])

            Divider()

            Button("AI") {
                appModel.selectResource(.aiAssistant)
            }

            Button("Settings") {
                appModel.selectResource(.settings)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandMenu("Resource") {
            Button("Copy Current Route Identity") {
                copyToPasteboard(appModel.selectedRouteIdentityText)
            }
            .disabled(appModel.selectedRouteIdentityText == nil)

            Button("Copy Open Detail Identity") {
                resourceDetailCommandContext?.copyIdentity()
            }
            .disabled(resourceDetailCommandContext == nil)

            Divider()

            Button("Open Detail Overview") {
                resourceDetailCommandContext?.selectPanel(.overview)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Open Detail Events") {
                resourceDetailCommandContext?.selectPanel(.events)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Open Detail Logs") {
                resourceDetailCommandContext?.selectPanel(.logs)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Open Detail Containers") {
                resourceDetailCommandContext?.selectPanel(.containers)
            }
            .keyboardShortcut("4", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Open Detail Environment") {
                resourceDetailCommandContext?.selectPanel(.environment)
            }
            .keyboardShortcut("5", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Open YAML") {
                resourceDetailCommandContext?.selectPanel(.yaml)
            }
            .keyboardShortcut("y", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Copy YAML") {
                resourceDetailCommandContext?.copyYAML()
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Button("Save YAML...") {
                resourceDetailCommandContext?.saveYAML()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!canUseDetailCommands)

            Divider()

            Button("Open Logs For Current Resource") {
                resourceDetailCommandContext?.selectPanel(.logs)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            .disabled(!canUseDetailCommands)
        }
    }

    private var canUseDetailCommands: Bool {
        resourceDetailCommandContext?.isLoaded == true
    }

    private func copyToPasteboard(_ text: String?) {
        guard let text, !text.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
