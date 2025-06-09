//
//  Task.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import Foundation

struct Task: Identifiable {
    let id: UUID = UUID()
    let title: String
    let dueDate: Date?
    let createdAt: Date = Date()
    
    // Formatted due date string with smart formatting
    var formattedDueDate: String {
        guard let dueDate = dueDate else {
            return "No due date"
        }
        
        // Format with date and time
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: dueDate)
    }
    
    // Smart due date display for task lists
    var dueDateDisplay: String {
        guard let dueDate = dueDate else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: dueDate)
    }
    
    // Check if the task is overdue
    var isOverdue: Bool {
        if let dueDate = dueDate {
            return dueDate < Date()
        }
        return false
    }
    
    // Time remaining until due date (for UI indicators)
    var timeRemaining: String {
        guard let dueDate = dueDate else { return "No deadline" }
        
        if isOverdue {
            return "Overdue"
        }
        
        // Calculate time remaining
        let calendar = Calendar.current
        let components = calendar.dateComponents([.day, .hour, .minute], from: Date(), to: dueDate)
        
        if let days = components.day, days > 0 {
            return "\(days) \(days == 1 ? "day" : "days") left"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours) \(hours == 1 ? "hour" : "hours") left"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") left"
        } else {
            return "Due now"
        }
    }
} 