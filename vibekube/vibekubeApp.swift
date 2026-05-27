//
//  vibekubeApp.swift
//  vibekube
//
//  Created by art on 27.05.2026.
//

import SwiftUI
import CoreData

@main
struct vibekubeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
