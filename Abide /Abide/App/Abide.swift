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
struct Abide: App {
    @StateObject private var authManager = FirebaseAuthManager()
    
    init() {
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        
        // Disable Firestore to prevent database corruption issues
        #if canImport(FirebaseFirestore)
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        let db = Firestore.firestore()
        db.settings = settings
        print("🔄 Firestore persistence disabled")
        #endif
        #endif
    }
    
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
                // Ensure authentication state is properly managed on app launch
                // This will clear any persisted state and require fresh login
                authManager.checkAuthenticationStatus()
            }
        }
    }
}
