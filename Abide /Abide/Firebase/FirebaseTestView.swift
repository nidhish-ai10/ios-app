//
//  FirebaseTestView.swift
//  TEST
//
//  Created by AI Assistant on 6/19/25.
//

import SwiftUI

// Only compile this if Firebase is available
#if canImport(FirebaseCore) && canImport(FirebaseAuth)
import FirebaseCore
import FirebaseAuth

struct FirebaseTestView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var testResults: [String] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🔥 Firebase Connection Test")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Button("Test Firebase Connection") {
                    testFirebaseConnection()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading)
                
                if isLoading {
                    ProgressView("Testing...")
                        .padding()
                }
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(testResults, id: \.self) { result in
                            HStack {
                                if result.contains("✅") {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else if result.contains("❌") {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                } else {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                }
                                
                                Text(result)
                                    .font(.caption)
                                    .multilineTextAlignment(.leading)
                                
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Firebase Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func testFirebaseConnection() {
        isLoading = true
        testResults.removeAll()
        
        Task {
            await performFirebaseTests()
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func performFirebaseTests() async {
        await MainActor.run {
            testResults.append("🔍 Starting Firebase Tests...")
        }
        
        // Test 1: Check if Firebase is configured
        await testFirebaseConfiguration()
        
        // Test 2: Test Authentication availability
        await testAuthenticationAvailability()
        
        // Test 3: Try creating a test user (will fail if not configured)
        await testUserCreation()
        
        await MainActor.run {
            testResults.append("✅ Firebase testing completed!")
        }
    }
    
    private func testFirebaseConfiguration() async {
        await MainActor.run {
            if FirebaseApp.app() != nil {
                testResults.append("✅ Firebase is configured and initialized")
                testResults.append("📱 App Name: \(FirebaseApp.app()?.name ?? "Unknown")")
                if let options = FirebaseApp.app()?.options {
                    testResults.append("🔑 Project ID: \(options.projectID ?? "Not set")")
                    testResults.append("📧 Client ID: \(String(options.googleAppID.prefix(20)))...")
                }
            } else {
                testResults.append("❌ Firebase is not configured properly")
                testResults.append("💡 Make sure GoogleService-Info.plist is added to your project")
            }
        }
    }
    
    private func testAuthenticationAvailability() async {
        await MainActor.run {
            let auth = Auth.auth()
            if auth.currentUser != nil {
                testResults.append("✅ User is currently signed in")
                testResults.append("👤 User ID: \(auth.currentUser?.uid ?? "Unknown")")
                testResults.append("📧 Email: \(auth.currentUser?.email ?? "No email")")
            } else {
                testResults.append("ℹ️ No user currently signed in (this is normal)")
            }
            
            testResults.append("✅ Firebase Auth is available and ready")
        }
    }
    
    private func testUserCreation() async {
        await MainActor.run {
            testResults.append("🧪 Testing user creation with dummy data...")
        }
        
        do {
            // Try to create a test user
            let testEmail = "test-\(UUID().uuidString.prefix(8))@firebase-test.com"
            let testPassword = "testpassword123"
            
            let authResult = try await Auth.auth().createUser(withEmail: testEmail, password: testPassword)
            
            await MainActor.run {
                testResults.append("✅ Test user created successfully!")
                testResults.append("🎉 Firebase Authentication is working!")
                testResults.append("👤 Test User ID: \(authResult.user.uid)")
            }
            
            // Clean up - delete the test user
            try await authResult.user.delete()
            
            await MainActor.run {
                testResults.append("🧹 Test user cleaned up successfully")
            }
            
        } catch {
            await MainActor.run {
                testResults.append("❌ Test user creation failed: \(error.localizedDescription)")
                if error.localizedDescription.contains("network") {
                    testResults.append("🌐 Check your internet connection")
                } else if error.localizedDescription.contains("auth") {
                    testResults.append("⚙️ Check Firebase Console: Authentication → Sign-in method → Email/Password")
                } else {
                    testResults.append("💡 Make sure Firebase project is set up correctly")
                }
            }
        }
    }
}

#else
// Fallback view when Firebase is not available
struct FirebaseTestView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Firebase SDK Not Installed")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Please install Firebase SDK first:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("1. File → Add Package Dependencies")
                Text("2. URL: https://github.com/firebase/firebase-ios-sdk")
                Text("3. Add: FirebaseAuth, FirebaseCore, FirebaseFirestore")
            }
            .font(.caption)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            
            Spacer()
        }
        .padding()
    }
}
#endif

#Preview {
    FirebaseTestView()
        .environmentObject(FirebaseAuthManager())
} 
