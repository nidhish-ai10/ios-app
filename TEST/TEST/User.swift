//
//  User.swift
//  TEST
//
//  Created by Valen Amarasingham on 6/20/25.
//

import Foundation

struct User: Identifiable, Codable {
    let id: String
    let email: String
    var displayName: String?
    
    init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}
