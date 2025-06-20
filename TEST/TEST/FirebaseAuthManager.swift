//
//  FirebaseAuthManager.swift
//  TEST
//
//  Created by AI Assistant on 6/19/25.
//

import SwiftUI

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseCore)
import FirebaseCore
#endif

// MARK: - Firebase Authentication Manager
@MainActor
class FirebaseAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    #if canImport(FirebaseAuth) && canImport(FirebaseFirestore)
    private let auth = Auth.auth()
    private var db: Firestore?
    #endif
    
    // App User data structure
    struct AppUser: Codable, Identifiable {
        let id: String
        let firstName: String
        let lastName: String
        let email: String
        let createdAt: Date
        
        var displayName: String {
            "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        }
    }
    
    init() {
        #if canImport(FirebaseAuth)
        // Disable Firestore to avoid corruption issues
        db = nil
        print("🔄 Running in Auth-only mode (Firestore disabled)")
        
        // Listen for authentication state changes
        auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    await self?.loadUserData(userId: user.uid)
                } else {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                }
            }
        }
        #else
        print("⚠️ Firebase not available - using offline mode")
        #endif
    }
    
    // MARK: - Authentication Methods
    
    /// Sign up with email and password
    func signUp(firstName: String, lastName: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        #if canImport(FirebaseAuth)
        do {
            // Input validation
            guard !firstName.isEmpty, !lastName.isEmpty, !email.isEmpty, !password.isEmpty else {
                throw AuthError.invalidInput("Please fill in all fields")
            }
            
            guard email.contains("@") && email.contains(".") else {
                throw AuthError.invalidInput("Please enter a valid email address")
            }
            
            guard password.count >= 6 else {
                throw AuthError.invalidInput("Password must be at least 6 characters")
            }
            
            // Create Firebase user
            let authResult = try await auth.createUser(withEmail: email, password: password)
            let userId = authResult.user.uid
            
            // Create user data (Auth-only mode)
            let userData = AppUser(
                id: userId,
                firstName: firstName,
                lastName: lastName,
                email: email,
                createdAt: Date()
            )
            
            // Save user data (Firestore disabled, so just set current user)
            currentUser = userData
            isAuthenticated = true
            
            print("✅ Firebase: User signed up successfully - \(userData.displayName)")
            
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
            print("❌ Firebase Auth Error: \(error.localizedDescription)")
        } catch {
            errorMessage = handleFirebaseError(error)
            print("❌ Firebase Error: \(error.localizedDescription)")
        }
        #else
        errorMessage = "Firebase not available. Please install Firebase SDK."
        print("❌ Firebase not available for signup")
        #endif
        
        isLoading = false
    }
    
    /// Sign in with email and password
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        #if canImport(FirebaseAuth)
        do {
            // Input validation
            guard !email.isEmpty, !password.isEmpty else {
                throw AuthError.invalidInput("Please fill in all fields")
            }
            
            guard email.contains("@") else {
                throw AuthError.invalidInput("Please enter a valid email address")
            }
            
            // Sign in with Firebase
            let authResult = try await auth.signIn(withEmail: email, password: password)
            let userId = authResult.user.uid
            
            // Load user data
            await loadUserData(userId: userId)
            
            print("✅ Firebase: User signed in successfully - \(currentUser?.displayName ?? email)")
            
        } catch let error as AuthError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = handleFirebaseError(error)
            print("❌ Firebase Sign In Error: \(error.localizedDescription)")
        }
        #else
        errorMessage = "Firebase not available. Please install Firebase SDK."
        print("❌ Firebase not available for signin")
        #endif
        
        isLoading = false
    }
    
    /// Sign out current user
    func signOut() {
        #if canImport(FirebaseAuth)
        do {
            try auth.signOut()
            currentUser = nil
            isAuthenticated = false
            errorMessage = nil
            print("✅ Firebase: User signed out successfully")
        } catch {
            errorMessage = "Failed to sign out. Please try again."
            print("❌ Firebase Sign Out Error: \(error.localizedDescription)")
        }
        #else
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        print("✅ Offline: User signed out")
        #endif
    }
    
    /// Reset password
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard !email.isEmpty, email.contains("@") else {
                throw AuthError.invalidInput("Please enter a valid email address")
            }
            
            try await auth.sendPasswordReset(withEmail: email)
            errorMessage = nil // Clear any previous errors
            print("✅ Firebase: Password reset email sent to \(email)")
            
        } catch {
            errorMessage = handleFirebaseError(error)
            print("❌ Firebase Password Reset Error: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    // MARK: - Firestore Methods
    
    /// Save user data to Firestore
    private func saveUserData(_ user: AppUser) async throws {
        guard let db = db else {
            print("⚠️ Firestore not available - user data not saved to database")
            return
        }
        
        let userData: [String: Any] = [
            "firstName": user.firstName,
            "lastName": user.lastName,
            "email": user.email,
            "createdAt": user.createdAt
        ]
        
        try await db.collection("users").document(user.id).setData(userData)
        print("✅ Firestore: User data saved for \(user.displayName)")
    }
    
    /// Load user data from Firestore
    private func loadUserData(userId: String) async {
        guard let db = db else {
            print("⚠️ Firestore not available - using basic user data")
            // Create a basic user object with available Auth info
            if let user = auth.currentUser {
                let basicUser = AppUser(
                    id: userId,
                    firstName: user.displayName?.components(separatedBy: " ").first ?? "User",
                    lastName: user.displayName?.components(separatedBy: " ").dropFirst().joined(separator: " ") ?? "",
                    email: user.email ?? "user@example.com",
                    createdAt: Date()
                )
                currentUser = basicUser
                isAuthenticated = true
            }
            return
        }
        
        do {
            let document = try await db.collection("users").document(userId).getDocument()
            
            if document.exists,
               let data = document.data(),
               let firstName = data["firstName"] as? String,
               let lastName = data["lastName"] as? String,
               let email = data["email"] as? String,
               let timestamp = data["createdAt"] as? Timestamp {
                
                let user = AppUser(
                    id: userId,
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    createdAt: timestamp.dateValue()
                )
                
                currentUser = user
                isAuthenticated = true
                
                print("✅ Firestore: User data loaded for \(user.displayName)")
            } else {
                print("⚠️ Firestore: User document not found for userId: \(userId)")
                // User exists in Auth but not in Firestore - create basic user
                if let authUser = auth.currentUser {
                    let basicUser = AppUser(
                        id: userId,
                        firstName: authUser.displayName?.components(separatedBy: " ").first ?? "User",
                        lastName: authUser.displayName?.components(separatedBy: " ").dropFirst().joined(separator: " ") ?? "",
                        email: authUser.email ?? "user@example.com",
                        createdAt: Date()
                    )
                    currentUser = basicUser
                    isAuthenticated = true
                }
            }
            
        } catch {
            print("❌ Firestore Load Error: \(error.localizedDescription)")
            // Fallback to basic auth user info
            if let authUser = auth.currentUser {
                let basicUser = AppUser(
                    id: userId,
                    firstName: authUser.displayName?.components(separatedBy: " ").first ?? "User",
                    lastName: authUser.displayName?.components(separatedBy: " ").dropFirst().joined(separator: " ") ?? "",
                    email: authUser.email ?? "user@example.com",
                    createdAt: Date()
                )
                currentUser = basicUser
                isAuthenticated = true
            }
        }
    }
    
    /// Check authentication status on app launch
    func checkAuthenticationStatus() {
        #if canImport(FirebaseAuth)
        // Check if there's a current user in Firebase Auth
        if let user = auth.currentUser {
            // User exists, load their data
            Task {
                await loadUserData(userId: user.uid)
            }
            print("🔍 Firebase: Found authenticated user - \(user.email ?? "Unknown")")
        } else {
            // No authenticated user
            currentUser = nil
            isAuthenticated = false
            print("🔍 Firebase: No authenticated user found")
        }
        #else
        print("🔍 Firebase: Not available - checking local auth status")
        // Fallback for when Firebase is not available
        isAuthenticated = false
        currentUser = nil
        #endif
    }
    
    /// Verify current authentication status - can be called periodically
    func verifyAuthenticationStatus() -> Bool {
        #if canImport(FirebaseAuth)
        let hasAuthUser = auth.currentUser != nil
        let hasCurrentUser = currentUser != nil
        let isMarkedAuthenticated = isAuthenticated
        
        // All three should be consistent
        if hasAuthUser && hasCurrentUser && isMarkedAuthenticated {
            return true
        } else {
            // Inconsistent state - sign out for security
            print("⚠️ Firebase: Inconsistent auth state detected - signing out")
            signOut()
            return false
        }
        #else
        return isAuthenticated && currentUser != nil
        #endif
    }
    
    // MARK: - Error Handling
    
    private func handleFirebaseError(_ error: Error) -> String {
        guard let authError = error as NSError? else {
            return "An unexpected error occurred. Please try again."
        }
        
        switch authError.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists. Please try signing in."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."
        case AuthErrorCode.weakPassword.rawValue:
            return "Password is too weak. Please choose a stronger password."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email. Please check your email or sign up."
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again."
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled. Please contact support."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection and try again."
        default:
            return "Authentication failed. Please try again."
        }
    }
}

// MARK: - Custom Auth Errors
enum AuthError: LocalizedError {
    case invalidInput(String)
    case networkError
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        case .networkError:
            return "Network connection error. Please check your internet connection."
        case .unknownError:
            return "An unexpected error occurred. Please try again."
        }
    }
} 