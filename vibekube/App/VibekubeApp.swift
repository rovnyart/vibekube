import SwiftUI

@main
struct VibekubeApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            VibekubeShellView()
                .environmentObject(appModel)
                .preferredColorScheme(appModel.appAppearance.preferredColorScheme)
                .frame(minWidth: 1080, minHeight: 680)
        }
        .commands {
            VibekubeCommands(appModel: appModel)
        }
    }
}

private extension AppAppearance {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
