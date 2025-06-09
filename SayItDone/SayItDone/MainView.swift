//
//  MainView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI

struct MainView: View {
    // Retrieve stored user name and login state
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showingProfileOptions = false
    @State private var showingSettingsView = false
    @State private var selectedTab = 1 // Default to Home tab
    
    // Pastel color palette
    let pastelBlue = Color(red: 190/255, green: 220/255, blue: 255/255)
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255)
    
    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                // Notifications Tab
                notificationsContent
                    .tabItem {
                        Image(systemName: "bell.fill")
                        Text("Notifications")
                    }
                    .tag(0)
                
                // Home Tab (Main Tasks View)
                homeContent
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(1)
                
                // Records Tab
                recordsContent
                    .tabItem {
                        Image(systemName: "doc.text.fill")
                        Text("Records")
                    }
                    .tag(2)
            }
            .accentColor(pastelBlueDarker) // Set the accent color for the tab bar
            .onAppear {
                // Set tab bar appearance
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                UITabBar.appearance().standardAppearance = appearance
                UITabBar.appearance().scrollEdgeAppearance = appearance
            }
            .navigationTitle(selectedTab == 0 ? "Notifications" : selectedTab == 1 ? "" : "Records")
            .navigationBarTitleDisplayMode(selectedTab == 1 ? .inline : .large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingProfileOptions) {
            AccountSheetView(isLoggedIn: $isLoggedIn, userFirstName: $userFirstName)
        }
        .sheet(isPresented: $showingSettingsView) {
            SettingsView()
        }
        .onAppear {
            setupNotificationObservers()
            
            // Apply dark mode setting on appear
            setAppearance()
        }
        .onChange(of: isDarkMode) { newValue in
            setAppearance()
        }
        .onDisappear {
            removeNotificationObservers()
        }
    }
    
    // MARK: - Tab Content Views
    
    private var notificationsContent: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.bottom, 10)
            
            Text("You have no new notifications")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    private var homeContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Use dynamic background color based on color scheme
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                // Main content - Now using TasksView for the main content
                VStack(spacing: 0) {
                    // Top bar with account button
                    HStack(alignment: .center) {
                        Spacer()
                        
                        // Account button - now opens settings directly
                        Button(action: {
                            showingSettingsView = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(pastelBlueDarker)
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(userFirstName.prefix(1)).uppercased())
                                            .foregroundColor(.white)
                                            .font(.system(size: 16, weight: .medium))
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                
                                // Small gear icon indicator at the bottom right
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Image(systemName: "gear")
                                            .font(.system(size: 10))
                                            .foregroundColor(pastelBlueDarker)
                                    )
                                    .offset(x: 12, y: 12)
                            }
                        }
                        .padding(.trailing, 16)
                        .accessibilityLabel("Settings")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    
                    // TasksView for the main task management functionality
                    TasksView()
                }
            }
        }
    }
    
    private var recordsContent: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.bottom, 10)
            
            Text("Your task history will appear here")
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    // Set the app appearance based on dark mode setting
    private func setAppearance() {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        window?.overrideUserInterfaceStyle = isDarkMode ? .dark : .light
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ShowSettingsView"),
            object: nil,
            queue: .main
        ) { _ in
            showingSettingsView = true
        }
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("ShowSettingsView"),
            object: nil
        )
    }
}

// Modern iOS-style Account Sheet View
struct AccountSheetView: View {
    @Binding var isLoggedIn: Bool
    @Binding var userFirstName: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with "Account" title
            Text("Account")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(UIColor.systemBackground))
                .overlay(
                    Divider().opacity(0.3),
                    alignment: .bottom
                )
            
            // User profile section
            HStack(spacing: 12) {
                // User avatar
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(userFirstName.prefix(1)))
                            .foregroundColor(.gray)
                    )
                
                // User name and "Account" label
                VStack(alignment: .leading, spacing: 2) {
                    Text(userFirstName)
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Account")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
            
            // Settings option
            Button(action: {
                // Settings action would go here
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NotificationCenter.default.post(name: Notification.Name("ShowSettingsView"), object: nil)
                }
            }) {
                HStack {
                    Image(systemName: "gear")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                    
                    Text("Settings")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            
            Divider()
            
            // Logout option
            Button(action: {
                userFirstName = ""
                isLoggedIn = false
                dismiss()
            }) {
                HStack {
                    Image(systemName: "arrow.right.square")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                    
                    Text("Logout")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            
            Spacer()
        }
        .background(Color(UIColor.systemGroupedBackground))
        .edgesIgnoringSafeArea(.bottom)
    }
}

#Preview {
    MainView()
} 