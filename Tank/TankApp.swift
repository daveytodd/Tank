//
//  TankApp.swift
//  Tank
//
//  Created by David Todd on 3/5/2026.
//

import SwiftUI
import CoreData

@main
struct TankApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
