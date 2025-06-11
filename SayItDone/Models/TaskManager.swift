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
    @Published var lastDeletedTask: Task? // Track last deleted task for potential undo
    @Published var isVerificationRequired = false
    @Published var pendingBatchOperation: (() -> Void)? = nil
    
    // Add a new task
    func addTask(title: String, dueDate: Date? = nil) -> UUID? {
        // Skip empty tasks
        if title.isEmpty {
            return nil
        }
        
        // Prevent duplicate tasks (check if a task with the same title was added in the last 3 seconds)
        let recentTime = Date().timeIntervalSince1970 - 3
        let hasDuplicate = tasks.contains { task in
            task.title.lowercased() == title.lowercased() && 
            task.createdAt.timeIntervalSince1970 > recentTime
        }
        
        if !hasDuplicate {
            let newTask = Task(title: title, dueDate: dueDate)
            tasks.append(newTask)
            return newTask.id
        }
        
        return nil
    }
    
    // Remove a task at a specific index
    func removeTask(at index: Int) {
        guard index >= 0 && index < tasks.count else { return }
        lastDeletedTask = tasks[index]
        tasks.remove(at: index)
    }
    
    // Remove a task by ID
    func removeTask(with id: UUID) {
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            lastDeletedTask = tasks[index]
        }
        tasks.removeAll { $0.id == id }
    }
    
    // Clear all completed tasks with verification
    func clearCompletedTasks(completion: @escaping (Bool) -> Void) {
        // Store the operation for execution after verification
        pendingBatchOperation = { [weak self] in
            guard let self = self else { return }
            self.tasks.removeAll()
            completion(true)
        }
        
        // Trigger verification
        isVerificationRequired = true
    }
    
    // Execute the pending operation after verification
    func executePendingOperation() {
        if let operation = pendingBatchOperation {
            operation()
            pendingBatchOperation = nil
        }
        isVerificationRequired = false
    }
    
    // Cancel the pending operation
    func cancelPendingOperation() {
        pendingBatchOperation = nil
        isVerificationRequired = false
    }
    
    // Undo last deletion if possible
    func undoLastDeletion() -> Bool {
        if let lastTask = lastDeletedTask {
            tasks.append(lastTask)
            lastDeletedTask = nil
            return true
        }
        return false
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