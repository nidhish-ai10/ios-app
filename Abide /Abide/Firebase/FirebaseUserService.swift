//
//  FirebaseUserService.swift
//  TEST
//
//  Created by Valen Amarasingham on 6/19/25.
//
import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine


class FirebaseUserService: ObservableObject {
   static let shared = FirebaseUserService()
   private let db = Firestore.firestore()
  
   @Published var currentUser: User?
   private var cancellables = Set<AnyCancellable>()
   private var authStateListenerHandle: AuthStateDidChangeListenerHandle?
  
   private init() {
       // Listen for auth state changes
       authStateListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
           if let user = user {
               self?.loadUserProfile(uid: user.uid)
           } else {
               self?.currentUser = nil
           }
       }
   }
   
   deinit {
       if let handle = authStateListenerHandle {
           Auth.auth().removeStateDidChangeListener(handle)
       }
   }
  
   // MARK: - User Profile Management
  
   func loadUserProfile(uid: String?) {
       guard let uid = uid else { return }
      
       let userDocRef = db.collection("users").document(uid)
      
       userDocRef.getDocument { [weak self] (document, error) in
           if let document = document, document.exists {
               if let data = document.data() {
                   let user = User(
                       id: uid,
                       email: data["email"] as? String ?? "",
                       displayName: data["name"] as? String
                   )
                   DispatchQueue.main.async {
                       self?.currentUser = user
                   }
               }
           } else {
               // First-time login: create default profile
               let defaultUser = User(
                   id: uid,
                   email: Auth.auth().currentUser?.email ?? "",
                   displayName: nil
               )
              
               userDocRef.setData([
                   "email": defaultUser.email,
                   "name": defaultUser.displayName ?? "",
                   "createdAt": Timestamp()
               ]) { err in
                   if let err = err {
                       print("Error creating user profile: \(err)")
                   } else {
                       DispatchQueue.main.async {
                           self?.currentUser = defaultUser
                       }
                   }
               }
           }
       }
   }
  
   // MARK: - Data Management
  
   func addUserData(_ data: [String: Any], completion: @escaping (Error?) -> Void) {
       guard let uid = currentUser?.id else {
           completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
           return
       }
      
       let userDocRef = db.collection("users").document(uid)
      
       // Add timestamp to the data
       var dataWithTimestamp = data
       dataWithTimestamp["timestamp"] = Timestamp()
      
       userDocRef.updateData(dataWithTimestamp) { error in
           completion(error)
       }
   }
  
   func getUserData(completion: @escaping ([String: Any]?, Error?) -> Void) {
       guard let uid = currentUser?.id else {
           completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
           return
       }
      
       let userDocRef = db.collection("users").document(uid)
      
       userDocRef.getDocument { (document, error) in
           if let error = error {
               completion(nil, error)
               return
           }
          
           if let document = document, document.exists {
               completion(document.data(), nil)
           } else {
               completion(nil, nil)
           }
       }
   }
  
   func updateUserData(fields: [String: Any], completion: @escaping (Error?) -> Void) {
       guard let uid = currentUser?.id else {
           completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
           return
       }
      
       let userDocRef = db.collection("users").document(uid)
      
       userDocRef.updateData(fields) { error in
           completion(error)
       }
   }
  
   // MARK: - Event Management
  
   func addEvent(eventType: String, eventData: [String: Any], completion: @escaping (Error?) -> Void) {
       guard let uid = currentUser?.id else {
           completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
           return
       }
      
       let eventRef = db.collection("users").document(uid).collection("events")
      
       let event: [String: Any] = [
           "user_id": uid,
           "event": eventType,
           "data": eventData,
           "timestamp": Timestamp()
       ]
      
       eventRef.addDocument(data: event) { error in
           completion(error)
       }
   }
  
   func getEvents(eventType: String? = nil, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
       guard let uid = currentUser?.id else {
           completion(nil, NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
           return
       }
      
       let eventsRef = db.collection("users").document(uid).collection("events")
       var query = eventsRef.order(by: "timestamp", descending: true)
      
       if let eventType = eventType {
           query = query.whereField("event", isEqualTo: eventType)
       }
      
       query.getDocuments { (snapshot, error) in
           if let error = error {
               completion(nil, error)
               return
           }
          
           let events = snapshot?.documents.compactMap { $0.data() } ?? []
           completion(events, nil)
       }
   }
  
   // MARK: - Conversation Analysis
  
   func storeConversationAnalysis(_ messages: [String]) async throws {
       // Get the analysis from the conversation analysis service
       guard let events = try await MemoryService.shared.analyzeSnippet(
           assistantMessage: messages[0],
           userMessage: messages[1]
       ) else {
           // No meaningful information found, nothing to store
           return
       }
       
       // Store each event individually
       for event in events {
           guard let eventType = event["event"] as? String,
                 let eventData = event["data"] as? [String: Any] else {
               continue
           }
           
           // Add user_id to the event data
           var dataWithUserId = eventData
           dataWithUserId["user_id"] = currentUser?.id
           
           try await addEventAsync(
               eventType: eventType,
               eventData: dataWithUserId
           )
       }
   }
   
   private func addEventAsync(eventType: String, eventData: [String: Any]) async throws {
       return try await withCheckedThrowingContinuation { continuation in
           addEvent(eventType: eventType, eventData: eventData) { error in
               if let error = error {
                   continuation.resume(throwing: error)
               } else {
                   continuation.resume()
               }
           }
       }
   }
   
   // MARK: - Conversation Analysis Integration
   
   /// Analyzes a single conversation snippet and stores events if meaningful information is found
   func analyzeSnippet(assistantMessage: String, userMessage: String) async throws {
       guard let events = try await MemoryService.shared.analyzeSnippet(
           assistantMessage: assistantMessage,
           userMessage: userMessage
       ) else {
           // No meaningful information found, nothing to store
           return
       }
       
       // Store each event individually
       for event in events {
           guard let eventType = event["event"] as? String,
                 let eventData = event["data"] as? [String: Any] else {
               continue
           }
           
           // Add user_id to the event data
           var dataWithUserId = eventData
           dataWithUserId["user_id"] = currentUser?.id
           
           try await addEventAsync(
               eventType: eventType,
               eventData: dataWithUserId
           )
       }
   }
    
    func backupMemoryToFirebase(_ memory: MemoryService.MemoryEvent, completion: @escaping (Error?) -> Void) {
        guard let uid = currentUser?.id else {
            completion(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user logged in"]))
            return
        }

        let memoryRef = db.collection("users").document(uid).collection("memories")

        let memoryData: [String: Any] = [
            "id": memory.id,
            "type": memory.type,
            "content": memory.content,
            "source": memory.source,
            "timestamp": memory.timestamp,
            "tags": memory.tags,
            "confidence": memory.confidence
        ]

        memoryRef.addDocument(data: memoryData) { error in
            completion(error)
        }
    }
    
    func syncFirebase() async throws {
        guard let uid = currentUser?.id else { return }

        let memoryRef = db.collection("users").document(uid).collection("memories")
        let snapshot = try await memoryRef.getDocuments()

        var newMemories: [MemoryService.MemoryEvent] = []

        for document in snapshot.documents {
            let data = document.data()
            guard let id = document.documentID as String?,
                  let type = data["type"] as? String,
                  let content = data["content"] as? String,
                  let source = data["source"] as? String,
                  let timestamp = data["timestamp"] as? Timestamp,
                  let tags = data["tags"] as? [String],
                  let confidence = data["confidence"] as? Double else {
                continue
            }

            let memory = MemoryService.MemoryEvent(
                id: id,
                type: type,
                content: content,
                source: source,
                timestamp: ISO8601DateFormatter().string(from: timestamp.dateValue()),
                tags: tags,
                confidence: confidence
            )

            // Check for duplicates in local storage
            if !MemoryService.shared.storedMemories.contains(where: { $0.id == memory.id }) {
                newMemories.append(memory)
            }
        }

        // Store to local UserDefaults
        try await MemoryService.shared.saveMemories(memories: newMemories)
    }
}
