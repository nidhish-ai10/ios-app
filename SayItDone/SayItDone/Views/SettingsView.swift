//
//  SettingsView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/4/25.
//

import SwiftUI
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("userEmail") private var userEmail: String = "user@example.com"
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    
    // Preferences
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("isSoundEnabled") private var isSoundEnabled = true
    
    // Simplified Notifications
    @AppStorage("isNotificationsEnabled") private var isNotificationsEnabled = true
    
    // Voice Input
    @AppStorage("isVoiceInputEnabled") private var isVoiceInputEnabled = true
    @State private var sensitivityValue: Double = 0.7
    @AppStorage("voiceSensitivity") private var voiceSensitivity: Double = 0.7
    @AppStorage("isAutomaticSilenceDetection") private var isAutomaticSilenceDetection = true
    
    // Security
    @AppStorage("isFaceIDEnabled") private var isFaceIDEnabled = false
    @AppStorage("isPrivacyModeEnabled") private var isPrivacyModeEnabled = false
    
    // App Info
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    
    // Backup & Sync
    @AppStorage("isCloudSyncEnabled") private var isCloudSyncEnabled = true
    @AppStorage("lastSyncTime") private var lastSyncTime: Double = Date().timeIntervalSince1970
    
    // For showing alerts
    @State private var showingLogoutAlert = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showingLicenses = false
    
    var body: some View {
        NavigationView {
            Form {
                // MARK: - Account Section
                Section(header: Text("Account")) {
                    HStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Text(String(userFirstName.prefix(1)).uppercased())
                                    .foregroundColor(.gray)
                                    .font(.system(size: 22, weight: .medium))
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(userFirstName)
                                .font(.headline)
                            Text(userEmail)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 8)
                    
                    Button(action: {
                        showingLogoutAlert = true
                    }) {
                        HStack {
                            Text("Logout")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "arrow.right.square")
                                .foregroundColor(.red)
                        }
                    }
                    .alert(isPresented: $showingLogoutAlert) {
                        Alert(
                            title: Text("Logout"),
                            message: Text("Are you sure you want to logout?"),
                            primaryButton: .destructive(Text("Logout")) {
                                userFirstName = ""
                                isLoggedIn = false
                                dismiss()
                            },
                            secondaryButton: .cancel()
                        )
                    }
                }
                
                // MARK: - Preferences Section
                Section(header: Text("Preferences")) {
                    Toggle("Dark Mode", isOn: $isDarkMode)
                        .onChange(of: isDarkMode) { _, newValue in
                            // Apply the color scheme change using the modern API
                            let scenes = UIApplication.shared.connectedScenes
                            let windowScene = scenes.first as? UIWindowScene
                            let window = windowScene?.windows.first
                            window?.overrideUserInterfaceStyle = newValue ? .dark : .light
                        }
                    
                    Toggle("Haptic Feedback", isOn: $isHapticsEnabled)
                    
                    Toggle("Sound Effects", isOn: $isSoundEnabled)
                }
                
                // MARK: - Simplified Notifications Section
                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $isNotificationsEnabled)
                }
                
                // MARK: - Voice Input Section
                Section(header: Text("Voice Input")) {
                    Toggle("Enable Voice Input", isOn: $isVoiceInputEnabled)
                    
                    if isVoiceInputEnabled {
                        Toggle("Auto-Detect Silence", isOn: $isAutomaticSilenceDetection)
                        
                        VStack(alignment: .leading) {
                            Text("Sensitivity: \(Int(sensitivityValue * 100))%")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            HStack {
                                Image(systemName: "speaker.wave.1")
                                    .foregroundColor(.gray)
                                
                                Slider(value: $sensitivityValue, in: 0...1, step: 0.05)
                                    .onChange(of: sensitivityValue) { _, newValue in
                                        voiceSensitivity = newValue
                                    }
                                    .onAppear {
                                        sensitivityValue = voiceSensitivity
                                    }
                                
                                Image(systemName: "speaker.wave.3")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // MARK: - Security & Privacy Section
                Section(header: Text("Security & Privacy")) {
                    Toggle("Face ID / Touch ID", isOn: $isFaceIDEnabled)
                        .onChange(of: isFaceIDEnabled) { _, newValue in
                            if newValue {
                                authenticateWithBiometrics()
                            }
                        }
                    
                    Toggle("Privacy Mode", isOn: $isPrivacyModeEnabled)
                        .onChange(of: isPrivacyModeEnabled) { _, _ in
                            // Would hide sensitive task content when enabled
                        }
                }
                
                // MARK: - Backup & Sync Section
                Section(header: Text("Backup & Sync")) {
                    Toggle("iCloud Sync", isOn: $isCloudSyncEnabled)
                    
                    HStack {
                        Text("Last Synchronized")
                        Spacer()
                        Text(lastSyncTimeFormatted)
                            .foregroundColor(.gray)
                    }
                    
                    Button(action: {
                        // Would trigger manual sync
                        lastSyncTime = Date().timeIntervalSince1970
                    }) {
                        HStack {
                            Text("Sync Now")
                            Spacer()
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                
                // MARK: - App Info Section
                Section(header: Text("App Info")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(appVersion) (\(buildNumber))")
                            .foregroundColor(.gray)
                    }
                    
                    NavigationLink(destination: LicensesView(), isActive: $showingLicenses) {
                        Text("Open Source Licenses")
                    }
                }
                
                // MARK: - Legal Section
                Section(header: Text("Legal")) {
                    NavigationLink(destination: PrivacyPolicyView(), isActive: $showingPrivacyPolicy) {
                        Text("Privacy Policy")
                    }
                    
                    NavigationLink(destination: TermsOfServiceView(), isActive: $showingTermsOfService) {
                        Text("Terms of Service")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper properties and methods
    
    var lastSyncTimeFormatted: String {
        let date = Date(timeIntervalSince1970: lastSyncTime)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Confirm your identity") { success, _ in
                DispatchQueue.main.async {
                    if !success {
                        // Failed authentication
                        isFaceIDEnabled = false
                    }
                }
            }
        } else {
            // Biometrics not available
            isFaceIDEnabled = false
        }
    }
}

// MARK: - Supporting Views

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                Text("Last updated: June 4, 2025")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom, 16)
                
                Text("This Privacy Policy describes how your personal information is collected, used, and shared when you use the SayItDone application.")
                
                Text("Information We Collect")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text("When you use our app, we collect the information you provide, such as your name and tasks. If you enable voice input, we process your voice recordings to convert them to text, but we do not store the recordings.")
                
                Text("How We Use Your Information")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text("We use the information we collect to provide and improve our service, including managing your tasks and preferences.")
                
                // Additional privacy policy content would go here
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Terms of Service")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.bottom, 8)
                
                Text("Last updated: June 4, 2025")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.bottom, 16)
                
                Text("Welcome to SayItDone! These Terms of Service govern your use of our application.")
                
                Text("1. Acceptance of Terms")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text("By using SayItDone, you agree to these Terms of Service. If you do not agree, please do not use the application.")
                
                Text("2. Changes to Terms")
                    .font(.headline)
                    .padding(.top, 8)
                
                Text("We may modify these terms at any time. Your continued use of the application constitutes acceptance of the modified terms.")
                
                // Additional terms of service content would go here
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicensesView: View {
    var body: some View {
        List {
            Section(header: Text("Open Source Libraries")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftUI")
                        .font(.headline)
                    Text("Copyright © Apple Inc.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("Used for building the user interface")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }
                .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speech Recognition")
                        .font(.headline)
                    Text("Copyright © Apple Inc.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    Text("Used for voice input and transcription")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.top, 2)
                }
                .padding(.vertical, 8)
                
                // Additional libraries would be listed here
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
} 