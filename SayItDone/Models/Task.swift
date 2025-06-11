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
    
    // Generate a heading from the task title
    var heading: String {
        // If title is empty, provide a default
        if title.isEmpty {
            return "Untitled Task"
        }
        
        // If title is already short, use it as is
        if title.count <= 30 {
            return formatHeading(title)
        }
        
        // Try to find a natural break point (sentence, comma, or period)
        if let periodRange = title.range(of: ".") {
            let firstSentence = title[..<periodRange.lowerBound]
            if firstSentence.count <= 40 {
                return formatHeading(String(firstSentence))
            }
        }
        
        if let commaRange = title.range(of: ",") {
            let firstPart = title[..<commaRange.lowerBound]
            if firstPart.count <= 40 {
                return formatHeading(String(firstPart))
            }
        }
        
        // Look for a break at a word boundary
        let words = title.components(separatedBy: " ")
        var heading = ""
        var wordCount = 0
        
        for word in words {
            if heading.count + word.count > 30 && wordCount >= 3 {
                break
            }
            
            if !heading.isEmpty {
                heading += " "
            }
            
            heading += word
            wordCount += 1
        }
        
        // If we have a heading, add ellipsis
        if heading != title {
            heading += "..."
        }
        
        return formatHeading(heading)
    }
    
    // Helper method to properly format and capitalize a heading
    private func formatHeading(_ text: String) -> String {
        guard !text.isEmpty else { return "Untitled Task" }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Capitalize first letter only if it's not already capitalized
        if let firstChar = trimmedText.first, !firstChar.isUppercase {
            let capitalizedFirstChar = String(firstChar).uppercased()
            let restOfText = trimmedText.dropFirst()
            return capitalizedFirstChar + restOfText
        }
        
        return trimmedText
    }
    
    // Formatted due date string with smart formatting
    var formattedDueDate: String {
        guard let dueDate = dueDate else {
            return "No due date"
        }
        
        let calendar = Calendar.current
        let hasTime = !calendar.isDate(dueDate, equalTo: calendar.startOfDay(for: dueDate), toGranularity: .hour)
        
        // Format with month, day, year, and time if specified
        let formatter = DateFormatter()
        if hasTime {
            formatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        } else {
            formatter.dateFormat = "MMMM d, yyyy"
        }
        return formatter.string(from: dueDate)
    }
    
    // Smart due date display for task lists
    var dueDateDisplay: String {
        guard let dueDate = dueDate else {
            return ""
        }
        
        let calendar = Calendar.current
        
        // Check if time was specified (not midnight)
        let hasTime = !calendar.isDate(dueDate, equalTo: calendar.startOfDay(for: dueDate), toGranularity: .hour)
        
        // Get actual date formatting (month and day)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        let actualDateString = dateFormatter.string(from: dueDate)
        
        // Time formatter
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeString = timeFormatter.string(from: dueDate)
        
        // Always show the actual date - with inline time format
        if hasTime {
            return "\(actualDateString), \(timeString)"
        } else {
            return actualDateString
        }
    }
    
    // Helper method to format date as "Month Day" (e.g. "June 15")
    private func formatDateMonthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date)
    }
    
    // Check if date is within the next 7 days
    private func isWithinNextWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysLater = calendar.date(byAdding: .day, value: 7, to: today)!
        return date <= sevenDaysLater
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