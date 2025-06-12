import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var authService: AuthenticationService
    
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                Text("Create Account")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 40)
                
                // Email Field
                VStack(alignment: .leading) {
                    Text("Email")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    TextField("Enter your email", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
                
                // Password Field
                VStack(alignment: .leading) {
                    Text("Password")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    SecureField("Enter your password", text: $password)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.newPassword)
                }
                
                // Confirm Password Field
                VStack(alignment: .leading) {
                    Text("Confirm Password")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    SecureField("Confirm your password", text: $confirmPassword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.newPassword)
                }
                
                // Sign Up Button
                Button {
                    signUp()
                } label: {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Sign Up")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isLoading)
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func signUp() {
        // Validate inputs
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            showError = true
            return
        }
        
        guard !password.isEmpty else {
            errorMessage = "Please enter a password"
            showError = true
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            showError = true
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            showError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                try await authService.signUp(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = authService.error?.message ?? "An error occurred during sign up"
                    showError = true
                }
            }
        }
    }
}

#Preview {
    SignUpView(authService: AuthenticationService())
} 