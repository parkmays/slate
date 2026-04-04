import AppKit
import Foundation
import SLATESharedTypes

// DeliveryTarget and DeliveryMethod are defined in SLATESharedTypes/Clip.swift.
// This file imports them rather than redefining locally.

public actor NotificationService {
    public static let shared = NotificationService()

    public func deliver(projectName: String, shareURL: URL, targets: [DeliveryTarget]) async {
        for target in targets {
            switch target.method {
            case .iMessage:
                await deliverViaiMessage(target: target, projectName: projectName, url: shareURL)
            case .email:
                await deliverViaEmail(target: target, projectName: projectName, url: shareURL)
            case .slack:
                await deliverViaSlack(target: target, projectName: projectName, url: shareURL)
            }
        }
    }

    private func deliverViaiMessage(target: DeliveryTarget, projectName: String, url: URL) async {
        let message = "[SLATE] \(projectName) dailies are ready. Review → \(url.absoluteString)"
        let script = """
        tell application "Messages"
            set targetBuddy to "\(target.address)"
            set targetService to (1st service whose service type is iMessage)
            set theBuddy to buddy targetBuddy of targetService
            send "\(message)" to theBuddy
        end tell
        """
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let err = error {
                print("[NotificationService] iMessage error: \(err)")
            }
        }
    }

    // email via SendGrid REST API (key from Keychain):
    private func deliverViaEmail(target: DeliveryTarget, projectName: String, url: URL) async {
        // POST https://api.sendgrid.com/v3/mail/send
        // Authorization: Bearer {SENDGRID_API_KEY from Keychain}
        // body: { "to": [{"email": target.address}], "subject": "[SLATE] \(projectName) ready",
        //         "content": [{"type":"text/plain", "value": "Review → \(url)"}] }
        
        // Get API key from Keychain
        guard let apiKey = getSecretFromKeychain(service: "SLATE", account: "SendGridAPIKey") else {
            print("[NotificationService] SendGrid API key not found in Keychain")
            return
        }
        
        let url = URL(string: "https://api.sendgrid.com/v3/mail/send")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "personalizations": [[
                "to": [["email": target.address]],
                "subject": "[SLATE] \(projectName) dailies are ready"
            ]],
            "from": ["email": "noreply@mountaintoppictures.com", "name": "SLATE"],
            "content": [[
                "type": "text/plain",
                "value": "Review dailies here: \(url.absoluteString)"
            ]]
        ] as [String : Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 202 {
                    print("[NotificationService] Email delivery failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[NotificationService] Email delivery error: \(error)")
        }
    }

    private func deliverViaSlack(target: DeliveryTarget, projectName: String, url: URL) async {
        // POST target.address (webhook URL) with { "text": "[SLATE] \(projectName) → \(url)" }
        let url = URL(string: target.address)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "text": "[SLATE] *\(projectName)* dailies are ready. Review → \(url.absoluteString)"
        ] as [String: Any]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 200 {
                    print("[NotificationService] Slack delivery failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("[NotificationService] Slack delivery error: \(error)")
        }
    }
    
    private func getSecretFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
}
