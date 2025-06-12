//
//  SayItDoneApp.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct SayItDoneApp: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @AppStorage("isDarkMode") private var isDarkMode = false
    @StateObject private var authService = AuthenticationService()
    
    init() {
        // Apply dark mode setting on app launch using the modern API
        setAppearance()
    }
    
    // Function to set the app appearance based on the isDarkMode setting
    private func setAppearance() {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        window?.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
    }
    
    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                // User is logged in, show the main view which incorporates TasksView
                MainView(authService: authService)
                    .onChange(of: isDarkMode) { _, newValue in
                        // Update appearance when dark mode setting changes
                        setAppearance()
                    }
            } else {
                // User is not logged in, show the login view
                LoginView(authService: authService)
                    .onChange(of: isDarkMode) { _, newValue in
                        // Update appearance when dark mode setting changes
                        setAppearance()
                    }
            }
        }
    }
}
