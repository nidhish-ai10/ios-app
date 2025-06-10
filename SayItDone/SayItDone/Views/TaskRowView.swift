//
//  TaskRowView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI

struct TaskRowView: View {
    let task: TodoTask
    let onDelete: () -> Void
    
    @State private var isSwiped = false
    @State private var offset: CGFloat = 0
    
    var body: some View {
        HStack {
            // Task content
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                if task.dueDate != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(task.dueDateDisplay)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Delete button
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .padding()
            }
            .opacity(isSwiped ? 1 : 0)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
        .offset(x: offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if gesture.translation.width < 0 {
                        offset = gesture.translation.width
                        isSwiped = true
                    }
                }
                .onEnded { gesture in
                    withAnimation {
                        if gesture.translation.width < -50 {
                            offset = -80
                            isSwiped = true
                        } else {
                            offset = 0
                            isSwiped = false
                        }
                    }
                }
        )
    }
}

#Preview {
    TaskRowView(
        task: TodoTask(
            title: "Sample Task",
            dueDate: Date()
        ),
        onDelete: {}
    )
} 