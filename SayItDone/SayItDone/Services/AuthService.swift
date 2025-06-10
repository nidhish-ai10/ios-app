import Foundation

enum AuthError: Error {
    case invalidCredentials
    case networkError
    case unknown
    
    var message: String {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError:
            return "Network error occurred"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

class AuthService: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    
    func login(email: String, password: String) async throws {
        // TODO: Implement actual API call to your backend
        // This is a mock implementation
        do {
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            // Mock validation
            if email.isEmpty || password.isEmpty {
                throw AuthError.invalidCredentials
            }
            
            // Mock successful login
            let user = User(id: UUID().uuidString, email: email)
            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            throw AuthError.unknown
        }
    }
    
    func logout() {
        currentUser = nil
        isAuthenticated = false
    }
}

struct User: Codable {
    let id: String
    let email: String
} 