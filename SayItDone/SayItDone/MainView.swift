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
    @State private var showingProfileOptions = false
    @State private var showingSettingsView = false
    
    // Pastel color palette
    let pastelBlue = Color(red: 190/255, green: 220/255, blue: 255/255)
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255)
    
    // Add these state variables after the existing state variables
    @State private var currentTaglineIndex = 0
    @State private var taglineOpacity = 1.0
    @State private var isAnimating = false
    
    // Add the taglines array below the color definitions
    // Collection of taglines to display in rotation
    let taglines = [
        "Structure your day, your way.",
        "Own your time, your style.",
        "Plan smart. Live better.",
        "Design your day with ease.",
        "Your day, your direction.",
        "Organize life. Your way.",
        "Make time work for you.",
        "Master your minutes.",
        "Take charge of today.",
        "Create calm in your chaos.",
        "Productivity, personalized.",
        "Shape your schedule.",
        "Every task, on your terms.",
        "Simplify. Plan. Achieve.",
        "Because your time matters.",
        "Streamline your schedule."
    ]
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.white.edgesIgnoringSafeArea(.all)
                    
                    // Main content - Now using TasksView for the main content
                    VStack(spacing: 0) {
                        // Top header with greeting and account button aligned horizontally
                        HStack(alignment: .center) {
                            // Empty spacer with width equal to account button for balance
                            Spacer()
                                .frame(width: 38)
                            
                            // Greeting and tagline section (centered)
                            VStack(alignment: .center, spacing: 5) {
                                // Personalized greeting
                                HStack(spacing: 3) {
                                    Text("Hi, ")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.black)
                                    
                                    Text("\(userFirstName)")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(pastelBlueDarker)
                                    
                                    Text("!")
                                        .font(.system(size: 28, weight: .bold))
                                        .foregroundColor(.black)
                                }
                                
                                // Rotating tagline with animation
                                Text(taglines[currentTaglineIndex])
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.gray)
                                    .opacity(taglineOpacity)
                                    .animation(.easeInOut(duration: 0.7), value: taglineOpacity)
                                    .frame(height: 20) // Fixed height to prevent layout shifts
                            }
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                // Start the tagline rotation
                                startTaglineRotation()
                            }
                            
                            // Account button
                            Button(action: {
                                showingProfileOptions = true
                            }) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 22))
                                    .foregroundColor(pastelBlueDarker)
                            }
                            .frame(width: 38)
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        
                        // TasksView for the main task management functionality
                        TasksView()
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingProfileOptions) {
                AccountSheetView(isLoggedIn: $isLoggedIn, userFirstName: $userFirstName)
            }
            .sheet(isPresented: $showingSettingsView) {
                SettingsView()
            }
            .onAppear {
                setupNotificationObservers()
            }
            .onDisappear {
                removeNotificationObservers()
            }
        }
    }
    
    // Add this method to the MainView struct
    // Method to handle tagline rotation with animation
    private func startTaglineRotation() {
        // Create a repeating timer to change taglines
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            // Don't start new animation if one is in progress
            if !isAnimating {
                isAnimating = true
                
                // Fade out current tagline
                withAnimation(.easeOut(duration: 0.7)) {
                    taglineOpacity = 0.0
                }
                
                // After fade out, change the tagline and fade in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    // Move to next tagline
                    currentTaglineIndex = (currentTaglineIndex + 1) % taglines.count
                    
                    // Fade in new tagline
                    withAnimation(.easeIn(duration: 0.7)) {
                        taglineOpacity = 1.0
                    }
                    
                    // Animation complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                        isAnimating = false
                    }
                }
            }
        }
        
        // Trigger timer immediately for first cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Ensure animation starts with the current tagline visible
            taglineOpacity = 1.0
        }
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