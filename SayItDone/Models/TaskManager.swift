//
//  TaskManager.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import Foundation
import Combine
import SwiftUI

class TaskManager: ObservableObject {
    @Published var tasks: [Task] = []
    private var deletedTasks: [Task] = []
    private var sortMethod: SortMethod = .creationTime
    private var pendingOperationTask: Task?
    private var pendingOperationType: OperationType?
    
    @Published var isVerificationRequired = false
    
    // Add a performant ID generation mechanism
    private var lastTaskID: UUID = UUID()
    
    enum SortMethod {
        case creationTime
        case dueDate
    }
    
    enum OperationType {
        case clearAll
        case removeOverdue
    }
    
    // Optimized task addition with direct return of UUID
    func addTask(title: String, dueDate: Date?) -> UUID {
        print("DEBUG: Adding task with title: \(title)")
        
        // Generate a new ID more efficiently
        lastTaskID = UUID()
        
        // Create the task with the pre-generated ID
        let newTask = Task(id: lastTaskID, title: title, dueDate: dueDate)
        
        // Add the task to the array immediately on the current thread
        tasks.append(newTask)
        print("DEBUG: Task added, current task count: \(tasks.count)")
        
        // Then sort in the background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.sortTasksBackground()
        }
        
        // Return the ID immediately for animations
        return lastTaskID
    }
    
    // Background sorting that doesn't block the main thread
    private func sortTasksBackground() {
        let sortedTasks: [Task]
        
        switch sortMethod {
        case .creationTime:
            sortedTasks = tasks.sorted { $0.id.uuidString > $1.id.uuidString }
        case .dueDate:
            sortedTasks = tasks.sorted { first, second in
                // Tasks with no due date go to the bottom
                if first.dueDate == nil && second.dueDate == nil {
                    return first.id.uuidString > second.id.uuidString // Fall back to creation time
                } else if first.dueDate == nil {
                    return false
                } else if second.dueDate == nil {
                    return true
                } else {
                    return first.dueDate! < second.dueDate!
                }
            }
        }
        
        // Update on main thread only if order changed
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.tasks != sortedTasks {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.tasks = sortedTasks
                }
            }
        }
    }
    
    // Optimized task removal method
    func removeTask(_ task: Task) {
        // Store task for undo functionality
        deletedTasks.append(task)
        
        // Find index using faster method
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Remove with animation
                withAnimation(.easeOut(duration: 0.2)) {
                    self.tasks.remove(at: index)
                }
            }
        }
    }
    
    // For backward compatibility
    func removeTask(with id: UUID) {
        if let task = tasks.first(where: { $0.id == id }) {
            removeTask(task)
        }
    }
    
    // Optimized undo implementation
    func undoLastDeletion() -> Bool {
        guard let lastDeleted = deletedTasks.popLast() else {
            return false
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Add back with animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.tasks.append(lastDeleted)
                self.sortTasks()
            }
        }
        
        return true
    }
    
    // Public sort method that can be called directly
    func sortTasks() {
        let sortedTasks: [Task]
        
        switch sortMethod {
        case .creationTime:
            sortedTasks = tasks.sorted { $0.id.uuidString > $1.id.uuidString }
        case .dueDate:
            sortedTasks = tasks.sorted { first, second in
                // Tasks with no due date go to the bottom
                if first.dueDate == nil && second.dueDate == nil {
                    return first.id.uuidString > second.id.uuidString // Fall back to creation time
                } else if first.dueDate == nil {
                    return false
                } else if second.dueDate == nil {
                    return true
                } else {
                    return first.dueDate! < second.dueDate!
                }
            }
        }
        
        // Update on main thread
        if Thread.isMainThread {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.tasks = sortedTasks
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.tasks = sortedTasks
                }
            }
        }
    }
    
    // MARK: - Additional operations (with verification prompt)
    
    func requestClearAllTasks() {
        pendingOperationType = .clearAll
        pendingOperationTask = nil
        isVerificationRequired = true
    }
    
    func requestRemoveOverdueTasks() {
        pendingOperationType = .removeOverdue
        pendingOperationTask = nil
        isVerificationRequired = true
    }
    
    func executePendingOperation() {
        defer {
            // Reset verification state
            pendingOperationType = nil
            pendingOperationTask = nil
            isVerificationRequired = false
        }
        
        // Execute the pending operation
        if let operationType = pendingOperationType {
            switch operationType {
            case .clearAll:
                clearAllTasks()
            case .removeOverdue:
                removeOverdueTasks()
            }
        }
    }
    
    func cancelPendingOperation() {
        pendingOperationType = nil
        pendingOperationTask = nil
        isVerificationRequired = false
    }
    
    // Clear all tasks
    private func clearAllTasks() {
        // Store for potential undo
        deletedTasks = tasks
        
        // Clear tasks with animation
        withAnimation(.easeOut(duration: 0.3)) {
            tasks.removeAll()
        }
    }
    
    // Remove overdue tasks
    private func removeOverdueTasks() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        
        // Get overdue tasks
        let overdueTasks = tasks.filter { task in
            if let dueDate = task.dueDate {
                return calendar.startOfDay(for: dueDate) < today
            }
            return false
        }
        
        // Store for undo
        deletedTasks.append(contentsOf: overdueTasks)
        
        // Remove overdue tasks
        withAnimation {
            tasks.removeAll { task in
                if let dueDate = task.dueDate {
                    return calendar.startOfDay(for: dueDate) < today
                }
                return false
            }
        }
    }
    
    // Change sort method
    func setSortMethod(_ method: SortMethod) {
        sortMethod = method
        sortTasks()
    }
    
    // Direct method for immediate task display
    func addTaskDirectly(_ task: Task) {
        print("DEBUG: Adding task directly with ID: \(task.id), title: \(task.title)")
        
        // Add task directly to the array - support multiple tasks
        tasks.insert(task, at: 0) // Add at the top for immediate visibility
        print("DEBUG: Task added directly, current task count: \(tasks.count)")
        
        // Sort tasks in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.sortTasksBackground()
        }
    }
    
    // Method to clear all tasks immediately (for testing/debugging)
    func clearAllTasksImmediately() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.tasks.removeAll()
            }
        }
    }
    
    // Enhanced duplicate detection method - less strict to allow similar tasks
    func hasDuplicateTask(title: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Only consider it a duplicate if it's exactly the same (very strict matching)
        return tasks.contains { existingTask in
            let existingTitle = existingTask.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Only block if titles are exactly identical
            return existingTitle == normalizedTitle
        }
    }
    
    // More lenient task addition - allows multiple similar tasks
    func addTaskIfNotDuplicate(title: String, dueDate: Date?) -> (success: Bool, taskID: UUID?) {
        print("TaskManager: Adding task '\(title)'")
        
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Only prevent if it's an exact match within the last 1 second (to prevent immediate duplicates only)
        let recentDuplicates = tasks.filter { existingTask in
            let existingTitle = existingTask.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let timeDifference = Date().timeIntervalSince(existingTask.createdAt)
            return existingTitle == normalizedTitle && timeDifference < 1.0
        }
        
        if !recentDuplicates.isEmpty {
            print("TaskManager: Recent duplicate detected, skipping")
            return (false, nil)
        }
        
        // Generate a new ID more efficiently
        lastTaskID = UUID()
        
        // Create the task with the pre-generated ID
        let newTask = Task(id: lastTaskID, title: title, dueDate: dueDate)
        
        // CRITICAL FIX: Ensure UI updates happen on main thread
        if Thread.isMainThread {
            // Add the task with animation to trigger @Published notification
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                tasks.append(newTask)
            }
            print("TaskManager: Task added, total: \(tasks.count)")
        } else {
            // If not on main thread, dispatch to main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    self.tasks.append(newTask)
                }
                print("TaskManager: Task added (dispatched), total: \(self.tasks.count)")
            }
        }
        
        // Then sort in the background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.sortTasksBackground()
        }
        
        // Return success and the ID immediately for animations
        return (true, lastTaskID)
    }
} 