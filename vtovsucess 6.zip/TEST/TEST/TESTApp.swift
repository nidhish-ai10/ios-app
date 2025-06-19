//
//  TESTApp.swift
//  TEST
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import SwiftUI
import SwiftData

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

@main
struct TESTApp: App {
    @StateObject private var authManager = FirebaseAuthManager()
    
    init() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        
        // Disable Firestore to prevent database corruption issues
        #if canImport(FirebaseFirestore)
        let settings = FirestoreSettings()
        settings.isPersistenceEnabled = false
        let db = Firestore.firestore()
        db.settings = settings
        print("🔄 Firestore persistence disabled")
        #endif
        #endif
    }
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            // Authentication guard - only show main content if authenticated
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                        .environmentObject(authManager)
                } else {
                    AuthenticationView()
                        .environmentObject(authManager)
                }
            }
            .onAppear {
                // Check authentication status on app launch
                authManager.checkAuthenticationStatus()
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
