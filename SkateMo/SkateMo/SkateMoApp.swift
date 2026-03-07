//
//  SkateMoApp.swift
//  SkateMo
//
//  Created by Justin Jiang on 11/24/25.
//

import SwiftUI

@main
struct SkateMoApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
