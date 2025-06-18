import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthenticationService
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var showSignUp = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Logo or App Name
            Text("SayItDone")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 60)
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
                    .textContentType(.password)
            }
            
            // Login Button
            Button {
                isLoading = true
                Task {
                    do {
                        try await authService.signIn(email: email, password: password)
                    } catch {
                        showError = true
                    }
                    isLoading = false
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text("Sign In")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .disabled(isLoading)
            
            // Sign Up Link
            HStack {
                Text("Don't have an account?")
                    .foregroundColor(.gray)
                Button("Sign Up") {
                    showSignUp = true
                }
                .foregroundColor(.blue)
            }
            .font(.subheadline)
            .padding(.top, 8)
            
            Spacer()
        }
        .padding()
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(authService.error?.message ?? "An error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView(authService: authService)
        }
    }
}

#Preview {
    LoginView(authService: AuthenticationService())
} 