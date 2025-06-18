import Foundation
import Combine
import FirebaseAuth

enum AuthenticationError: Error {
    case invalidCredentials
    case networkError
    case unknownError
    
    var message: String {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error occurred"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

class AuthenticationService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var error: AuthenticationError?
    
    private var handle: AuthStateDidChangeListenerHandle?
    
    init() {
        // Set up auth state listener
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            
            if let user = user {
                // User is signed in
                let appUser = User(id: user.uid, email: user.email ?? "")
                self.currentUser = appUser
                self.isAuthenticated = true
            } else {
                // User is signed out
                self.currentUser = nil
                self.isAuthenticated = false
            }
        }
    }
    
    deinit {
        // Remove auth state listener when service is deallocated
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    func signIn(email: String, password: String) async throws {
        do {
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            let user = User(id: authResult.user.uid, email: authResult.user.email ?? "")
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.error = nil
                UserDefaults.standard.set(user.email, forKey: "userEmail")
            }
        } catch {
            await MainActor.run {
                self.error = .invalidCredentials
                self.isAuthenticated = false
            }
            throw AuthenticationError.invalidCredentials
        }
    }
    
    func signUp(email: String, password: String) async throws {
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            let user = User(id: authResult.user.uid, email: authResult.user.email ?? "")
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
                self.error = nil
                UserDefaults.standard.set(user.email, forKey: "userEmail")
            }
        } catch {
            await MainActor.run {
                self.error = .unknownError
                self.isAuthenticated = false
            }
            throw AuthenticationError.unknownError
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
        } catch {
            self.error = .unknownError
        }
    }
} 