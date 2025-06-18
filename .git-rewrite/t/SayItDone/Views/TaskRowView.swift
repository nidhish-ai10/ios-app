//
//  TaskRowView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI
import LocalAuthentication

struct TaskRowView: View {
    let task: TodoTask
    let onDelete: (TodoTask) -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @State private var deleteConfirmation = false
    @State private var authenticationError = false
    @State private var authenticationErrorMessage = ""
    
    // Add task ID for better SwiftUI view identification
    private let viewID = UUID()
    
    var body: some View {
        ZStack {
            // Background for delete action - only show when swiped
            if isSwiped || offset < -10 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.red)
                    .overlay(
                        HStack {
                            Spacer()
                            Image(systemName: "trash.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(.trailing, 25)
                        }
                    )
            }
            
            // Task content
            HStack(spacing: 15) {
                // Task completion circle
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 25, height: 25)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 23, height: 23)
                    )
                
                // Task details with optimized layout
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.heading)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    if let dueDate = task.dueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            Text(task.formattedDueDate())
                                .font(.caption)
                                .foregroundColor(task.isOverdue() ? .red : .gray)
                        }
                    }
                }
                .padding(.vertical, 10)
                
                Spacer()
            }
            .padding(.horizontal, 15)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        // Only allow right-to-left swipe (negative offset)
                        if gesture.translation.width < 0 {
                            offset = gesture.translation.width
                        }
                    }
                    .onEnded { gesture in
                        withAnimation(.spring()) {
                            if gesture.translation.width < -100 {
                                // Swiped far enough to trigger delete
                                isSwiped = true
                                offset = -60
                            } else {
                                // Reset position
                                isSwiped = false
                                offset = 0
                            }
                        }
                    }
            )
            .onTapGesture {
                // Reset swipe if tapped
                if isSwiped {
                    withAnimation(.spring()) {
                        isSwiped = false
                        offset = 0
                    }
                }
            }
        }
        .frame(height: 70)
        .padding(.horizontal)
        .alert(isPresented: $deleteConfirmation) {
            Alert(
                title: Text("Complete Task"),
                message: Text("Are you sure you want to mark \"\(task.heading)\" as complete and remove it?"),
                primaryButton: .destructive(Text("Complete")) {
                    authenticateAndDelete()
                },
                secondaryButton: .cancel {
                    // Reset swipe on cancel
                    withAnimation(.spring()) {
                        isSwiped = false
                        offset = 0
                    }
                }
            )
        }
        .alert(isPresented: $authenticationError) {
            Alert(
                title: Text("Authentication Failed"),
                message: Text(authenticationErrorMessage),
                dismissButton: .default(Text("OK")) {
                    // Reset swipe on dismiss
                    withAnimation(.spring()) {
                        isSwiped = false
                        offset = 0
                    }
                }
            )
        }
        .overlay(
            // Delete button overlay with improved tap target
            Group {
                if isSwiped {
                    Button(action: {
                        deleteConfirmation = true
                    }) {
                        Image(systemName: "trash.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 60, height: 70)
                            .background(Color.red)
                            .cornerRadius(10)
                    }
                    .position(x: UIScreen.main.bounds.width - 30, y: 35)
                    .transition(.opacity)
                }
            }
        )
        // Use a unique identifier for this view instance
        .id(viewID)
    }
    
    private func authenticateAndDelete() {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            let reason = "Authenticate to delete task"
            
            // Attempt authentication
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    if success {
                        // Authentication successful, delete the task
                        onDelete(task)
                    } else {
                        // Authentication failed
                        withAnimation(.spring()) {
                            isSwiped = false
                            offset = 0
                        }
                        
                        // Get username from UserDefaults for personalized message
                        let userName = UserDefaults.standard.string(for: .userNameKey) ?? "user"
                        
                        // Set error message
                        if let error = error as? LAError {
                            switch error.code {
                            case .userCancel:
                                authenticationErrorMessage = "Authentication cancelled."
                            case .userFallback:
                                authenticationErrorMessage = "Passcode authentication cancelled."
                            case .biometryNotAvailable:
                                authenticationErrorMessage = "Face ID/Touch ID is not available on this device."
                            case .biometryNotEnrolled:
                                authenticationErrorMessage = "Face ID/Touch ID is not set up on this device."
                            default:
                                authenticationErrorMessage = "Only \(userName) can delete tasks."
                            }
                        } else {
                            authenticationErrorMessage = "Only \(userName) can delete tasks."
                        }
                        
                        authenticationError = true
                    }
                }
            }
        } else {
            // Biometric authentication not available
            withAnimation(.spring()) {
                isSwiped = false
                offset = 0
            }
            
            // Get username from UserDefaults for personalized message
            let userName = UserDefaults.standard.string(for: .userNameKey) ?? "user"
            
            // Set error message based on the specific error
            if let error = error as? LAError {
                switch error.code {
                case .biometryNotAvailable:
                    authenticationErrorMessage = "Face ID/Touch ID is not available on this device."
                case .biometryNotEnrolled:
                    authenticationErrorMessage = "Face ID/Touch ID is not set up on this device."
                default:
                    authenticationErrorMessage = "Only \(userName) can delete tasks."
                }
            } else {
                authenticationErrorMessage = "Only \(userName) can delete tasks."
            }
            
            authenticationError = true
        }
    }
}

// MARK: - Extensions
extension UserDefaults {
    func string(for key: UserDefaultsKeys) -> String? {
        return string(forKey: key.rawValue)
    }
}

enum UserDefaultsKeys: String {
    case userNameKey = "userName"
} 