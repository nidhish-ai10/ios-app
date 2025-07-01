//
//  FirebaseAuthManager.swift
//  TEST
//
//  Created by Bairineni Nidhish Rao on 6/19/25.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
class FirebaseAuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let auth = Auth.auth()
    private let freshInstallKey = "app_fresh_install"
    private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
    
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
        if checkIfFreshInstall() {
            // Clear any existing Firebase Auth state on fresh install
            clearAuthenticationState()
        }
        
        // Disable Firebase Auth persistence to prevent auto-login after app deletion
        do {
            try auth.useUserAccessGroup(nil)
        } catch {
            print("Failed to disable Firebase Auth persistence: \(error)")
        }
        
        authStateListenerHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if let user = user {
                    await self?.loadUserData(userId: user.uid)
                } else {
                    self?.currentUser = nil
                    self?.isAuthenticated = false
                }
            }
        }
    }
    
    deinit {
        if let handle = authStateListenerHandle {
            auth.removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Fresh Install Detection
    
    /// Checks if this is a fresh install of the app
    private func checkIfFreshInstall() -> Bool {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: Constants.is_a_freshInstall)
        
        if !hasLaunchedBefore {
            // First time launching the app
            UserDefaults.standard.set(true, forKey: Constants.is_a_freshInstall)
            return true
        }
        
        return false
    }
    
    // MARK: - Authentication State Management
    
    /// Clears all authentication state to ensure fresh login after app reinstallation
    private func clearAuthenticationState() {
        // Sign out any existing user
        do {
            try auth.signOut()
        } catch {
            print("Error signing out during initialization: \(error)")
        }
        
        // Clear local state
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        
        // Clear any stored authentication data
        UserDefaults.standard.removeObject(forKey: Constants.firebase_auth_persistence)
    }
    
    /// Call this method when you want to ensure user must log in again
    func forceSignOut() {
        clearAuthenticationState()
    }
    
    /// Utility method
    func resetToFreshInstall() {
        UserDefaults.standard.removeObject(forKey: Constants.is_a_freshInstall)
        clearAuthenticationState()
    }
    
    func signUp(firstName: String, lastName: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard !firstName.isEmpty, !lastName.isEmpty,
                  !email.isEmpty, !password.isEmpty else {
                throw AuthError.invalidInput("Please fill in all fields")
            }
            
            guard email.contains("@") else {
                throw AuthError.invalidInput("Please enter a valid email address")
            }
            
            let authResult = try await auth.createUser(withEmail: email, password: password)
            let userData = AppUser(
                id: authResult.user.uid,
                firstName: firstName,
                lastName: lastName,
                email: email,
                createdAt: Date()
            )
            
            currentUser = userData
            isAuthenticated = true
            
        } catch {
            errorMessage = handleFirebaseError(error)
        }
        
        isLoading = false
    }
    
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard !email.isEmpty, !password.isEmpty else {
                throw AuthError.invalidInput("Please fill in all fields")
            }
            
            let authResult = try await auth.signIn(withEmail: email, password: password)
            await loadUserData(userId: authResult.user.uid)
            
        } catch {
            errorMessage = handleFirebaseError(error)
        }
        
        isLoading = false
    }
    
    func signOut() {
        do {
            try auth.signOut()
            currentUser = nil
            isAuthenticated = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to sign out. Please try again."
        }
    }
    
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard !email.isEmpty, email.contains("@") else {
                throw AuthError.invalidInput("Please enter a valid email address")
            }
            
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = handleFirebaseError(error)
        }
        
        isLoading = false
    }
    
    private func loadUserData(userId: String) async {
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
    }
    
    func checkAuthenticationStatus() {
        // Check if this is a fresh install first
        let isFreshInstall = checkIfFreshInstall()
        
        if isFreshInstall {
            // Clear authentication state on fresh install
            clearAuthenticationState()
            return
        }
        
        // Check current Firebase Auth state
        if let user = auth.currentUser {
            Task {
                await loadUserData(userId: user.uid)
            }
        } else {
            currentUser = nil
            isAuthenticated = false
        }
    }
    
    private func handleFirebaseError(_ error: Error) -> String {
        guard let authError = error as NSError? else {
            return "An unexpected error occurred. Please try again."
        }
        
        switch authError.code {
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            return "An account with this email already exists."
        case AuthErrorCode.invalidEmail.rawValue:
            return "Please enter a valid email address."
        case AuthErrorCode.weakPassword.rawValue:
            return "Please choose a stronger password."
        case AuthErrorCode.userNotFound.rawValue:
            return "No account found with this email."
        case AuthErrorCode.wrongPassword.rawValue:
            return "Incorrect password. Please try again."
        case AuthErrorCode.userDisabled.rawValue:
            return "This account has been disabled."
        case AuthErrorCode.tooManyRequests.rawValue:
            return "Too many attempts. Please try again later."
        case AuthErrorCode.networkError.rawValue:
            return "Network error. Please check your connection."
        default:
            return "Authentication failed. Please try again."
        }
    }
}

enum AuthError: LocalizedError {
    case invalidInput(String)
    case networkError
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .invalidInput(let message): return message
        case .networkError: return "Network connection error."
        case .unknownError: return "An unexpected error occurred."
        }
    }
} 
