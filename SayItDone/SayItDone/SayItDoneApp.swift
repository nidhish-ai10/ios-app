//
//  SayItDoneApp.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI

@main
struct SayItDoneApp: App {
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("isDarkMode") private var isDarkMode = false
    
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
            if isLoggedIn {
                // User is logged in, show the main view which incorporates TasksView
                MainView()
                    .onChange(of: isDarkMode) { _, _ in
                        // Update appearance when dark mode setting changes
                        setAppearance()
                    }
            } else {
                // User is not logged in, show the login/welcome view
                ContentView()
                    .onChange(of: isDarkMode) { _, _ in
                        // Update appearance when dark mode setting changes
                        setAppearance()
                    }
                    .onDisappear {
                        // When ContentView disappears after submission, set the app storage values
                        if !userFirstName.isEmpty {
                            isLoggedIn = true
                        }
                    }
            }
        }
    }
}
