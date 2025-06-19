//
//  AuthenticationView.swift
//  TEST
//
//  Created by AI Assistant on 6/19/25.
//

import SwiftUI

// MARK: - Authentication Manager
@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Simple user data structure
    struct User: Codable {
        let id: String
        let firstName: String
        let lastName: String
        let email: String
        let password: String
    }
    
    // Simple user database simulation
    private func saveUser(_ user: User) {
        var users = getStoredUsers()
        // Remove existing user with same email if exists
        users.removeAll { $0.email == user.email }
        users.append(user)
        
        if let data = try? JSONEncoder().encode(users) {
            UserDefaults.standard.set(data, forKey: "storedUsers")
        }
    }
    
    private func getStoredUsers() -> [User] {
        guard let data = UserDefaults.standard.data(forKey: "storedUsers"),
              let users = try? JSONDecoder().decode([User].self, from: data) else {
            return []
        }
        return users
    }
    
    private func getUserByEmail(_ email: String) -> User? {
        return getStoredUsers().first { $0.email == email }
    }
    
    // Mock authentication - replace with real authentication service
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Mock validation
        if email.isEmpty || password.isEmpty {
            errorMessage = "Please fill in all fields"
            isLoading = false
            return
        }
        
        if !email.contains("@") {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            isLoading = false
            return
        }
        
        // Check if user exists in our user database
        guard let storedUser = getUserByEmail(email) else {
            errorMessage = "Account not found. Please sign up first."
            isLoading = false
            return
        }
        
        // Verify password (in a real app, you'd hash and compare)
        if storedUser.password != password {
            errorMessage = "Incorrect password. Please try again."
            isLoading = false
            return
        }
        
        // Successful login - create user object without password for security
        let user = User(
            id: storedUser.id,
            firstName: storedUser.firstName,
            lastName: storedUser.lastName,
            email: storedUser.email,
            password: "" // Don't store password in current user
        )
        
        currentUser = user
        isAuthenticated = true
        isLoading = false
        
        // Store login state
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        UserDefaults.standard.set(email, forKey: "userEmail")
        UserDefaults.standard.set(storedUser.firstName, forKey: "userFirstName")
        UserDefaults.standard.set(storedUser.lastName, forKey: "userLastName")
        print("✅ User signed in successfully: \(storedUser.firstName) \(storedUser.lastName) - \(email)")
    }
    
    func signUp(firstName: String, lastName: String, email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Mock validation
        if firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty {
            errorMessage = "Please fill in all fields"
            isLoading = false
            return
        }
        
        if !email.contains("@") {
            errorMessage = "Please enter a valid email address"
            isLoading = false
            return
        }
        
        if password.count < 6 {
            errorMessage = "Password must be at least 6 characters"
            isLoading = false
            return
        }
        
        // Check if user already exists
        if getUserByEmail(email) != nil {
            errorMessage = "An account with this email already exists. Please try signing in."
            isLoading = false
            return
        }
        
        // Create and save new user
        let user = User(
            id: UUID().uuidString,
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: password
        )
        
        // Save user to database
        saveUser(user)
        
        // Create current user object without password
        let currentUserData = User(
            id: user.id,
            firstName: firstName,
            lastName: lastName,
            email: email,
            password: "" // Don't store password in current user
        )
        
        currentUser = currentUserData
        isAuthenticated = true
        isLoading = false
        
        // Store login state
        UserDefaults.standard.set(true, forKey: "isLoggedIn")
        UserDefaults.standard.set(email, forKey: "userEmail")
        UserDefaults.standard.set(firstName, forKey: "userFirstName")
        UserDefaults.standard.set(lastName, forKey: "userLastName")
        print("✅ User signed up successfully: \(firstName) \(lastName) - \(email)")
    }
    
    func signOut() {
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
        
        // Clear stored login state
        UserDefaults.standard.removeObject(forKey: "isLoggedIn")
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "userFirstName")
        UserDefaults.standard.removeObject(forKey: "userLastName")
        print("✅ User signed out")
    }
    
    func checkAuthenticationStatus() {
        // Check if user was previously logged in
        let isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
        if isLoggedIn {
            let email = UserDefaults.standard.string(forKey: "userEmail") ?? ""
            
            // Try to get user from database first
            if let storedUser = getUserByEmail(email) {
                currentUser = User(
                    id: storedUser.id,
                    firstName: storedUser.firstName,
                    lastName: storedUser.lastName,
                    email: storedUser.email,
                    password: "" // Don't store password in current user
                )
                isAuthenticated = true
                print("✅ User auto-signed in: \(storedUser.firstName) \(storedUser.lastName)")
            } else {
                // Fallback to stored preferences (legacy support)
                let firstName = UserDefaults.standard.string(forKey: "userFirstName") ?? "User"
                let lastName = UserDefaults.standard.string(forKey: "userLastName") ?? ""
                
                currentUser = User(
                    id: UUID().uuidString,
                    firstName: firstName,
                    lastName: lastName,
                    email: email,
                    password: ""
                )
                isAuthenticated = true
                print("✅ User auto-signed in (legacy): \(firstName) \(lastName)")
            }
        }
    }
}

// MARK: - Authentication View
struct AuthenticationView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    @State private var isSignUpMode = false
    
    var body: some View {
        NavigationView {
                VStack(spacing: 0) {
                    // Header Section
                    VStack(spacing: 20) {
                        Spacer()
                        Spacer()
                    }
                    .frame(maxHeight: 300)
                    
                    // Form Section
                    VStack(spacing: 20) {
                        if isSignUpMode {
                            SignUpForm(authManager: authManager)
                        } else {
                            SignInForm(authManager: authManager)
                        }
                        
                        // Toggle between Sign In and Sign Up
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isSignUpMode.toggle()
                                authManager.errorMessage = nil
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(isSignUpMode ? "Already have an account?" : "Don't have an account?")
                                    .foregroundColor(.secondary)
                                Text(isSignUpMode ? "Sign In" : "Sign Up")
                                    .foregroundColor(.blue)
                                    .fontWeight(.medium)
                            }
                            .font(.subheadline)
                        }
                        .disabled(authManager.isLoading)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 50)
                }
                .background(Color(.systemBackground))
                .navigationBarHidden(true)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

// MARK: - Sign In Form
struct SignInForm: View {
    @ObservedObject var authManager: FirebaseAuthManager
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case email, password
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .email)
                    .disabled(authManager.isLoading)
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                SecureField("Enter your password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .disabled(authManager.isLoading)
            }
            
            // Error Message
            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Sign In Button
            Button(action: {
                focusedField = nil
                Task {
                    await authManager.signIn(email: email, password: password)
                }
            }) {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(authManager.isLoading ? "Signing In..." : "Sign In")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(signInButtonColor)
                )
                .foregroundColor(.white)
            }
            .disabled(authManager.isLoading || email.isEmpty || password.isEmpty)
        }
    }
    
    private var signInButtonColor: Color {
        if authManager.isLoading || email.isEmpty || password.isEmpty {
            return .gray
        } else {
            return .blue
        }
    }
}

// MARK: - Sign Up Form
struct SignUpForm: View {
    @ObservedObject var authManager: FirebaseAuthManager
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?
    
    enum Field {
        case firstName, lastName, email, password
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Name Fields Row
            HStack(spacing: 12) {
                // First Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("First Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    TextField("First name", text: $firstName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.givenName)
                        .focused($focusedField, equals: .firstName)
                        .disabled(authManager.isLoading)
                }
                
                // Last Name Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    TextField("Last name", text: $lastName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.familyName)
                        .focused($focusedField, equals: .lastName)
                        .disabled(authManager.isLoading)
                }
            }
            
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                TextField("Enter your email", text: $email)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .email)
                    .disabled(authManager.isLoading)
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                SecureField("Create a password (min. 6 characters)", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.newPassword)
                    .focused($focusedField, equals: .password)
                    .disabled(authManager.isLoading)
            }
            
            // Error Message
            if let errorMessage = authManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Sign Up Button
            Button(action: {
                focusedField = nil
                Task {
                    await authManager.signUp(
                        firstName: firstName,
                        lastName: lastName,
                        email: email,
                        password: password
                    )
                }
            }) {
                HStack {
                    if authManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(authManager.isLoading ? "Creating Account..." : "Create Account")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(signUpButtonColor)
                )
                .foregroundColor(.white)
            }
            .disabled(authManager.isLoading || !isFormValid)
        }
    }
    
    private var isFormValid: Bool {
        !firstName.isEmpty && !lastName.isEmpty && !email.isEmpty && !password.isEmpty
    }
    
    private var signUpButtonColor: Color {
        if authManager.isLoading || !isFormValid {
            return .gray
        } else {
            return .blue
        }
    }
}

// MARK: - Preview
#Preview {
    AuthenticationView()
} 