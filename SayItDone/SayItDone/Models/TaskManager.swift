//
//  TaskManager.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import Foundation
import Combine

class TaskManager: ObservableObject {
    @Published var tasks: [Task] = []
    
    // Add a new task
    func addTask(title: String, dueDate: Date? = nil) {
        let newTask = Task(title: title, dueDate: dueDate)
        tasks.append(newTask)
    }
    
    // Remove a task at a specific index
    func removeTask(at index: Int) {
        guard index >= 0 && index < tasks.count else { return }
        tasks.remove(at: index)
    }
    
    // Remove a task by ID
    func removeTask(with id: UUID) {
        tasks.removeAll { $0.id == id }
    }
    
    // Sort tasks by creation date (newest first)
    func sortByCreationDate() {
        tasks.sort { $0.createdAt > $1.createdAt }
    }
    
    // Sort tasks by due date (soonest first)
    func sortByDueDate() {
        tasks.sort { 
            if let date1 = $0.dueDate, let date2 = $1.dueDate {
                return date1 < date2
            } else if $0.dueDate != nil {
                return true
            } else {
                return false
            }
        }
    }
} 