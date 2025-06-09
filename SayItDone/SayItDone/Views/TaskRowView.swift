//
//  TaskRowView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI

struct TaskRowView: View {
    let task: Task
    let onDelete: () -> Void
    
    // State for UI interactions
    @State private var isPressed = false
    
    // User preferences
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Task completion circle with improved interaction
            Button(action: {
                // Provide haptic feedback when enabled
                if isHapticsEnabled {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                
                // Add a small delay for visual feedback before deletion
                withAnimation {
                    isPressed = true
                }
                
                // Delay deletion to show the animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDelete()
                }
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
                // Task title
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                // Only show due date info if there is a due date
                if task.dueDate != nil {
                    HStack(spacing: 6) {
                        // Calendar icon instead of clock
                        Image(systemName: task.isOverdue ? "exclamationmark.circle" : "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(task.isOverdue ? .red : .gray)
                        
                        // Due date with improved formatting
                        Text(task.dueDateDisplay)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(task.isOverdue ? .red : .gray)
                        
                        // Time remaining indicator
                        if !task.timeRemaining.isEmpty {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            
                            Text(task.timeRemaining)
                                .font(.system(size: 12, weight: task.isOverdue ? .medium : .regular))
                                .foregroundColor(task.isOverdue ? .red : .gray)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Delete button with improved interaction
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.gray.opacity(0.6))
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
    }
} 