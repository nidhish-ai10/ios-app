//
//  ContentView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI

struct ContentView: View {
    @State private var name = ""
    @FocusState private var isNameFieldFocused: Bool
    
    // AppStorage for user information
    @AppStorage("userFirstName") private var userFirstName: String = ""
    @AppStorage("isLoggedIn") private var isLoggedIn: Bool = false
    
    // Pastel color palette
    let pastelBlue = Color(red: 190/255, green: 220/255, blue: 255/255)
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255) // Darker version for active button
    let pastelLavender = Color(red: 200/255, green: 180/255, blue: 230/255)
    let pastelGray = Color(red: 140/255, green: 140/255, blue: 150/255)
    let pastelBackground = Color.white
    
    // Computed property for button background color
    private var buttonBackgroundColor: Color {
        return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pastelBlue : pastelBlueDarker
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                pastelBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Logo representation with mic to the left of text
                        VStack(spacing: 10) {
                            HStack(spacing: 15) {
                                // Mic icon - decreased size
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 240/255, green: 248/255, blue: 255/255))
                                        .frame(width: 50, height: 50)
                                    
                                    Image(systemName: "mic.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 22)
                                        .foregroundColor(.black)
                                }
                                
                                // App name
                                Text("Say")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.black) +
                                Text("It")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(pastelBlue) +
                                Text("Done")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundColor(.black)
                            }
                            
                            Text("Say it. Set it. Sorted.")
                                .font(.system(size: 14, weight: .light))
                                .foregroundColor(pastelGray)
                        }
                        .padding(.top, 30)
                        
                        Spacer()
                            .frame(height: 20)
                        
                        VStack(alignment: .leading, spacing: 20) {
                            // Updated prompt text
                            Text("First things first – what's your name?")
                                .font(.system(size: 17, weight: .regular))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 24)
                            
                            // Text field with iOS-style design
                            TextField("Type here", text: $name)
                                .padding()
                                .background(Color(UIColor.systemBackground))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                                )
                                .focused($isNameFieldFocused)
                                .padding(.horizontal, 24)
                                .submitLabel(.continue)
                                .onSubmit {
                                    submitName()
                                }
                            
                            // Continue button with dynamic background color
                            Button(action: {
                                submitName()
                            }) {
                                Text("Continue")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(buttonBackgroundColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                            .animation(.easeInOut(duration: 0.2), value: name)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(.vertical)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                }
                .navigationBarHidden(true)
            }
        }
    }
    
    private func submitName() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            // Dismiss keyboard
            isNameFieldFocused = false
            
            // Store the user's name in AppStorage
            userFirstName = trimmedName
            
            // Set logged in to true to immediately navigate to MainView
            isLoggedIn = true
        }
    }
}

#Preview {
    ContentView()
}
