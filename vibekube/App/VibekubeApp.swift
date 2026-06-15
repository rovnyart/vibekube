import SwiftUI

@main
struct VibekubeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            VibekubeShellView()
                .environmentObject(appModel)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .commands {
            VibekubeCommands(appModel: appModel)
        }
    }
}
