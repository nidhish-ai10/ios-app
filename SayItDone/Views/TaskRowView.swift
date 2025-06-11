//
//  TaskRowView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI
import LocalAuthentication

struct TaskRowView: View {
    let task: Task
    let onDelete: () -> Void
    
    // State for UI interactions
    @State private var isPressed = false
    @State private var appearAnimation = false
    @State private var showingDeleteConfirmation = false
    @State private var showingAuthenticationError = false
    
    // User preferences
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("isFaceIDEnabled") private var isFaceIDEnabled = true
    @AppStorage("userFirstName") private var userFirstName: String = ""
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Task completion circle with improved interaction
            Button(action: {
                // Provide haptic feedback when enabled
                if isHapticsEnabled {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                
                // Mark task as complete - process directly without confirmation
                completeTask()
            }) {
                Circle()
                    .strokeBorder(isPressed ? Color.green : Color.gray, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(isPressed ? Color.green.opacity(0.3) : Color.clear)
                            .frame(width: 22, height: 22)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(isPressed ? 1 : 0)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Task details with improved layout
            VStack(alignment: .leading, spacing: 6) {
                // Task heading instead of full title
                Text(task.heading)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Only show due date info if there is a due date
                if task.dueDate != nil {
                    HStack(spacing: 6) {
                        // Calendar icon
                        Image(systemName: task.isOverdue ? "exclamationmark.circle" : "calendar")
                            .font(.system(size: 14))
                            .foregroundColor(task.isOverdue ? .red : .gray)
                        
                        // Due date with improved formatting - more compact and elegant
                        Text(task.dueDateDisplay)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(task.isOverdue ? .red : .primary)
                        
                        // Check if time was specified (not midnight)
                        let calendar = Calendar.current
                        if let dueDate = task.dueDate, !calendar.isDate(dueDate, equalTo: calendar.startOfDay(for: dueDate), toGranularity: .hour) {
                            // Clock icon is no longer needed as time is integrated into the dueDateDisplay
                        }
                        
                        Spacer()
                        
                        // Time remaining indicator - moved to the right for better balance
                        if !task.timeRemaining.isEmpty {
                            Text(task.timeRemaining)
                                .font(.system(size: 12, weight: task.isOverdue ? .medium : .regular))
                                .foregroundColor(task.isOverdue ? .red : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 2)
                }
            }
            
            Spacer()
            
            // Delete button with improved interaction and red trash icon
            Button(action: {
                // Delete action - direct deletion with authentication if enabled
                if isHapticsEnabled {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                }
                
                if isFaceIDEnabled {
                    authenticateUser()
                } else {
                    // If authentication is not enabled, delete directly
                    completeTask()
                }
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
        )
        .padding(.vertical, 4)
        .opacity(appearAnimation ? 1 : 0.7)
        .scaleEffect(appearAnimation ? 1 : 0.97)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appearAnimation = true
            }
        }
        .alert("Authentication Failed", isPresented: $showingAuthenticationError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Only \(userFirstName.isEmpty ? "the account owner" : userFirstName) can delete tasks. Please try again.")
        }
    }
    
    // Method to handle task completion and deletion
    private func completeTask() {
        // Add a small delay for visual feedback before deletion
        withAnimation {
            isPressed = true
        }
        
        // Delay deletion to show the animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDelete()
        }
    }
    
    // Method to authenticate user with Face ID or Touch ID
    private func authenticateUser() {
        let context = LAContext()
        var error: NSError?
        
        // Check if biometric authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            // Authenticate with biometrics
            let reason = "Authenticate to delete task"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    if success {
                        // Authentication successful, delete the task
                        completeTask()
                    } else {
                        // Authentication failed, show error
                        showingAuthenticationError = true
                    }
                }
            }
        } else {
            // Fallback for when biometric authentication is not available
            // Use device passcode as fallback
            let reason = "Authenticate to delete task"
            
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                DispatchQueue.main.async {
                    if success {
                        // Authentication successful, delete the task
                        completeTask()
                    } else {
                        // Authentication failed, show error
                        showingAuthenticationError = true
                    }
                }
            }
        }
    }
} 