//
//  PersonalizeView.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import SwiftUI

struct PersonalizeView: View {
    @ObservedObject private var authStore = AuthSessionStore.shared
    @State private var name: String = ""
    @State private var emails: [String] = [""]
    @State private var phones: [String] = [""]
    @State private var additional: [String] = [""]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text("Personalize")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        
                        TextField("Enter your name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                            .onChange(of: name) { _ in
                                saveData()
                            }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Email section card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(emails.indices, id: \.self) { index in
                                HStack {
                                    TextField("Enter email address", text: $emails[index])
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14))
                                        .padding(12)
                                        .background(Color.clear)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                        )
                                        .onChange(of: emails[index]) { _ in
                                            saveData()
                                        }
                                    
                                    if index > 0 {
                                        Button("-") {
                                            emails.remove(at: index)
                                            saveData()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            
                            Button("+") {
                                emails.append("")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Phone section card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(phones.indices, id: \.self) { index in
                                HStack {
                                    TextField("Enter phone number", text: $phones[index])
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14))
                                        .padding(12)
                                        .background(Color.clear)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                        )
                                        .onChange(of: phones[index]) { _ in
                                            saveData()
                                        }
                                    
                                    if index > 0 {
                                        Button("-") {
                                            phones.remove(at: index)
                                            saveData()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            
                            Button("+") {
                                phones.append("")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                    
                    // Additional section card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Additional")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(additional.indices, id: \.self) { index in
                                HStack {
                                    TextField("Calendly: calendly.com/clippy", text: $additional[index])
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 14))
                                        .padding(12)
                                        .background(Color.clear)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                        )
                                        .onChange(of: additional[index]) { _ in
                                            saveData()
                                        }
                                    
                                    if index > 0 {
                                        Button("-") {
                                            additional.remove(at: index)
                                            saveData()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            
                            Button("+") {
                                if additional.count < 10 {
                                    additional.append("")
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .padding()
        .onAppear {
            loadData()
        }
        .onChange(of: authStore.userName) { newValue in
            // Sync name when it changes in ProfileSettingsView
            if let newName = newValue, !newName.isEmpty {
                name = newName
                UserDefaults.standard.set(newName, forKey: "personalize_name")
            }
        }
    }
    
    private func saveData() {
        let userDefaults = UserDefaults.standard
        
        // Save name - sync with AuthSessionStore
        userDefaults.set(name, forKey: "personalize_name")
        authStore.userName = name.isEmpty ? nil : name
        
        // Save emails with Primary/Other designation
        let emailValues = emails.compactMap { email in
            return email.isEmpty ? nil : email
        }
        var emailsWithType: [[String: String]] = []
        for (index, email) in emailValues.enumerated() {
            let type = index == 0 ? "Primary" : "Other"
            emailsWithType.append(["email": email, "type": type])
        }
        userDefaults.set(emailsWithType, forKey: "personalize_emails")
        
        // Save phones with Primary/Other designation
        let phoneValues = phones.compactMap { phone in
            return phone.isEmpty ? nil : phone
        }
        var phonesWithType: [[String: String]] = []
        for (index, phone) in phoneValues.enumerated() {
            let type = index == 0 ? "Primary" : "Other"
            phonesWithType.append(["phone": phone, "type": type])
        }
        userDefaults.set(phonesWithType, forKey: "personalize_phones")
        
        // Save additional fields
        let additionalValues = additional.compactMap { field in
            return field.isEmpty ? nil : field
        }
        userDefaults.set(additionalValues, forKey: "personalize_additional")
        
        Logger.info("=== PERSONALIZE DATA SAVED ===", module: "Settings")
        Logger.info("Name: \(name)", module: "Settings")
        Logger.info("Emails: \(emailsWithType)", module: "Settings")
        Logger.info("Phones: \(phonesWithType)", module: "Settings")
        Logger.info("Additional: \(additionalValues)", module: "Settings")
        Logger.info("==============================\n", module: "Settings")
        
        // Notify that user information has changed (triggers system prompt refresh)
        UserPersonalizationManager.shared.notifyUserInfoChanged()
    }
    
    private func loadData() {
        let userDefaults = UserDefaults.standard
        
        // Load name - prioritize AuthSessionStore (from ProfileSettingsView), fallback to UserDefaults
        if let authName = authStore.userName, !authName.isEmpty {
            name = authName
            // Also sync to UserDefaults for consistency
            userDefaults.set(authName, forKey: "personalize_name")
        } else if let savedName = userDefaults.string(forKey: "personalize_name") {
            name = savedName
        }
        
        // Load emails
        if let emailsData = userDefaults.array(forKey: "personalize_emails") as? [[String: String]] {
            emails = emailsData.compactMap { $0["email"] }
            if emails.isEmpty {
                emails = [""]
            }
        }
        
        // Load phones
        if let phonesData = userDefaults.array(forKey: "personalize_phones") as? [[String: String]] {
            phones = phonesData.compactMap { $0["phone"] }
            if phones.isEmpty {
                phones = [""]
            }
        }
        
        // Load additional
        if let additionalData = userDefaults.array(forKey: "personalize_additional") as? [String] {
            additional = additionalData
            if additional.isEmpty {
                additional = [""]
            }
        }
    }
}

#Preview {
    PersonalizeView()
}
