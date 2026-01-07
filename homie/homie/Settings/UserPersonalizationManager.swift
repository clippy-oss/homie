import Foundation

/// Manager for handling user personalization data
class UserPersonalizationManager {
    static let shared = UserPersonalizationManager()
    
    // Cached user information block (updated only when data changes)
    private var cachedUserInfoBlock: String = ""
    
    private init() {
        // Initialize cache on first access
        refreshUserInfoCache()
    }
    
    /// Refresh the cached user information block
    func refreshUserInfoCache() {
        cachedUserInfoBlock = buildUserInformationBlock()
        Logger.info("📊 UserPersonalizationManager: Cache refreshed", module: "Settings")
    }
    
    /// Get cached user information block (no dynamic retrieval)
    func getUserInformationBlock() -> String {
        return cachedUserInfoBlock
    }
    
    /// Build formatted user information string for LLM prompts
    private func buildUserInformationBlock() -> String {
        let userDefaults = UserDefaults.standard
        
        Logger.info("📊 UserPersonalizationManager: Loading user data from UserDefaults...", module: "Settings")
        
        var infoLines: [String] = []
        
        // Load name
        if let name = userDefaults.string(forKey: "personalize_name"), !name.isEmpty {
            Logger.info("   ✓ Found name: \(name)", module: "Settings")
            infoLines.append("Name: \(name)")
        } else {
            Logger.info("   ✗ No name found", module: "Settings")
        }
        
        // Load emails
        if let emailsData = userDefaults.array(forKey: "personalize_emails") as? [[String: String]] {
            Logger.info("   ℹ️ Found emails data: \(emailsData)", module: "Settings")
            let nonEmptyEmails: [(email: String, type: String)] = emailsData.compactMap { emailData in
                guard let email = emailData["email"], !email.isEmpty else { return nil }
                let type = emailData["type"] ?? "Other"
                return (email: email, type: type)
            }
            if !nonEmptyEmails.isEmpty {
                Logger.info("   ✓ Non-empty emails: \(nonEmptyEmails)", module: "Settings")
                let primaryEmails = nonEmptyEmails.filter { $0.type == "Primary" }
                let otherEmails = nonEmptyEmails.filter { $0.type == "Other" }
                
                var emailLines: [String] = []
                if !primaryEmails.isEmpty {
                    emailLines.append("Primary: \(primaryEmails.map { $0.email }.joined(separator: ", "))")
                }
                if !otherEmails.isEmpty {
                    emailLines.append("Other: \(otherEmails.map { $0.email }.joined(separator: ", "))")
                }
                infoLines.append("Email(s): \(emailLines.joined(separator: " | "))")
            } else {
                Logger.info("   ✗ All emails are empty", module: "Settings")
            }
        } else {
            Logger.info("   ✗ No emails array found", module: "Settings")
        }
        
        // Load phones
        if let phonesData = userDefaults.array(forKey: "personalize_phones") as? [[String: String]] {
            Logger.info("   ℹ️ Found phones data: \(phonesData)", module: "Settings")
            let nonEmptyPhones: [(phone: String, type: String)] = phonesData.compactMap { phoneData in
                guard let phone = phoneData["phone"], !phone.isEmpty else { return nil }
                let type = phoneData["type"] ?? "Other"
                return (phone: phone, type: type)
            }
            if !nonEmptyPhones.isEmpty {
                Logger.info("   ✓ Non-empty phones: \(nonEmptyPhones)", module: "Settings")
                let primaryPhones = nonEmptyPhones.filter { $0.type == "Primary" }
                let otherPhones = nonEmptyPhones.filter { $0.type == "Other" }
                
                var phoneLines: [String] = []
                if !primaryPhones.isEmpty {
                    phoneLines.append("Primary: \(primaryPhones.map { $0.phone }.joined(separator: ", "))")
                }
                if !otherPhones.isEmpty {
                    phoneLines.append("Other: \(otherPhones.map { $0.phone }.joined(separator: ", "))")
                }
                infoLines.append("Phone(s): \(phoneLines.joined(separator: " | "))")
            } else {
                Logger.info("   ✗ All phones are empty", module: "Settings")
            }
        } else {
            Logger.info("   ✗ No phones array found", module: "Settings")
        }
        
        // Load additional fields
        if let additional = userDefaults.array(forKey: "personalize_additional") as? [String] {
            Logger.info("   ℹ️ Found additional array: \(additional)", module: "Settings")
            let nonEmptyAdditional = additional.filter { !$0.isEmpty }
            if !nonEmptyAdditional.isEmpty {
                Logger.info("   ✓ Non-empty additional: \(nonEmptyAdditional)", module: "Settings")
                for item in nonEmptyAdditional {
                    infoLines.append(item)
                }
            } else {
                Logger.info("   ✗ All additional fields are empty", module: "Settings")
            }
        } else {
            Logger.info("   ✗ No additional fields array found", module: "Settings")
        }
        
        // If no personalization data exists, return empty string
        guard !infoLines.isEmpty else {
            Logger.info("📊 UserPersonalizationManager: No user data found, returning empty string", module: "Settings")
            return ""
        }
        
        Logger.info("📊 UserPersonalizationManager: Successfully loaded user data with \(infoLines.count) items", module: "Settings")
        
        // Format as a block
        let infoBlock = """
        
        User Information:
        \(infoLines.joined(separator: "\n"))
        """
        
        return infoBlock
    }
    
    /// Notify that user information has changed (call this when saving)
    func notifyUserInfoChanged() {
        refreshUserInfoCache()
        // Notify managers that need to rebuild their system instructions
        FoundationModelsManager.shared.refreshSystemInstructions()
        LLMRouter.shared.refreshSystemInstructions()
    }
    
    /// Check if any user information is available
    func hasUserInformation() -> Bool {
        let userDefaults = UserDefaults.standard
        
        // Check if name exists
        if let name = userDefaults.string(forKey: "personalize_name"), !name.isEmpty {
            return true
        }
        
        // Check if any emails exist
        if let emailsData = userDefaults.array(forKey: "personalize_emails") as? [[String: String]],
           emailsData.contains(where: { emailData in
               guard let email = emailData["email"] else { return false }
               return !email.isEmpty
           }) {
            return true
        }
        
        // Check if any phones exist
        if let phonesData = userDefaults.array(forKey: "personalize_phones") as? [[String: String]],
           phonesData.contains(where: { phoneData in
               guard let phone = phoneData["phone"] else { return false }
               return !phone.isEmpty
           }) {
            return true
        }
        
        // Check if any additional fields exist
        if let additional = userDefaults.array(forKey: "personalize_additional") as? [String],
           additional.contains(where: { !$0.isEmpty }) {
            return true
        }
        
        return false
    }
    
    /// Get user data as a dictionary for programmatic access
    func getUserData() -> [String: Any] {
        let userDefaults = UserDefaults.standard
        var userData: [String: Any] = [:]
        
        if let name = userDefaults.string(forKey: "personalize_name"), !name.isEmpty {
            userData["name"] = name
        }
        
        if let emailsData = userDefaults.array(forKey: "personalize_emails") as? [[String: String]] {
            let nonEmptyEmails: [String] = emailsData.compactMap { emailData in
                guard let email = emailData["email"], !email.isEmpty else { return nil }
                return email
            }
            if !nonEmptyEmails.isEmpty {
                userData["emails"] = nonEmptyEmails
            }
        }
        
        if let phonesData = userDefaults.array(forKey: "personalize_phones") as? [[String: String]] {
            let nonEmptyPhones: [String] = phonesData.compactMap { phoneData in
                guard let phone = phoneData["phone"], !phone.isEmpty else { return nil }
                return phone
            }
            if !nonEmptyPhones.isEmpty {
                userData["phones"] = nonEmptyPhones
            }
        }
        
        if let additional = userDefaults.array(forKey: "personalize_additional") as? [String] {
            let nonEmptyAdditional = additional.filter { !$0.isEmpty }
            if !nonEmptyAdditional.isEmpty {
                userData["additional"] = nonEmptyAdditional
            }
        }
        
        return userData
    }
}

