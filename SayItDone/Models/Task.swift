//
//  Task.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import Foundation

struct TodoTask: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let dueDate: Date?
    
    // Cache the heading to avoid recalculating it
    private let _heading: String
    
    // Computed property using cached value
    var heading: String {
        return _heading
    }
    
    // Initialize with an optional ID (for efficiency)
    init(id: UUID = UUID(), title: String, dueDate: Date? = nil) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.dueDate = dueDate
        
        // Pre-calculate heading during initialization
        self._heading = TodoTask.generateHeading(from: title)
    }
    
    // Static method to generate heading - moved to class method for testability
    private static func generateHeading(from title: String) -> String {
        // If title is empty, provide a default
        if title.isEmpty {
            return "Untitled Task"
        }
        
        // If title is already short, use it as is
        if title.count <= 60 {
            return title
        }
        
        // Get the first sentence or phrase
        if let firstSentenceRange = title.range(of: "[.!?]", options: .regularExpression) {
            let firstSentence = title[..<firstSentenceRange.upperBound].trimmingCharacters(in: .whitespacesAndNewlines)
            // Limit sentence length
            if firstSentence.count > 60 {
                let truncated = String(firstSentence.prefix(57)) + "..."
                return truncated
            }
            return firstSentence
        } else {
            // If no sentence terminator found
            let truncated = String(title.prefix(57)) + "..."
            return truncated
        }
    }
    
    // Format due date for display
    func formattedDueDate() -> String {
        guard let dueDate = dueDate else { return "" }
        
        // Check if time component is set (not midnight)
        let calendar = Calendar.current
        let dueDateTime = calendar.startOfDay(for: dueDate)
        let hasTimeComponent = !calendar.isDate(dueDate, equalTo: dueDateTime, toGranularity: .minute)
        
        // Always use exact date format
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        // Add time if present
        if hasTimeComponent {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            return "\(dateFormatter.string(from: dueDate)) at \(timeFormatter.string(from: dueDate))"
        } else {
            return dateFormatter.string(from: dueDate)
        }
    }
    
    // Check if task is overdue
    func isOverdue() -> Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date()
    }
    
    // Required for Equatable conformance
    static func == (lhs: TodoTask, rhs: TodoTask) -> Bool {
        return lhs.id == rhs.id
    }
    
    // Helper method to check if date is within the current week
    func isDateInCurrentWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysLater = calendar.date(byAdding: .day, value: 7, to: today)!
        return date <= sevenDaysLater && date >= today
    }
    
    // Time remaining until due date (for UI indicators)
    var timeRemaining: String {
        guard let dueDate = dueDate else { return "No deadline" }
        
        if isOverdue() {
            return "Overdue"
        }
        
        // Calculate time remaining in total hours
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: Date(), to: dueDate)
        let totalHours = (components.hour ?? 0)
        let minutes = components.minute ?? 0
        
        // Add an additional hour if there are significant minutes remaining
        let displayHours = minutes > 30 ? totalHours + 1 : totalHours
        
        if displayHours > 0 {
            return "\(displayHours) \(displayHours == 1 ? "hour" : "hours") left"
        } else if let minutes = components.minute, minutes > 0 {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes") left"
        } else {
            return "Due now"
        }
    }
} 