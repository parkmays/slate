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

    /// Sends the daily digest via email (SendGrid) and/or Slack. iMessage is skipped.
    public func deliverDigest(report: DigestReport, targets: [DeliveryTarget]) async {
        for target in targets {
            switch target.method {
            case .iMessage:
                continue
            case .email:
                await deliverDigestViaEmail(target: target, report: report)
            case .slack:
                await deliverDigestViaSlack(target: target, report: report)
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
        guard let apiKey = getSecretFromKeychain(service: "SLATE", account: "SendGridAPIKey") else {
            print("[NotificationService] SendGrid API key not found in Keychain")
            return
        }

        let endpoint = URL(string: "https://api.sendgrid.com/v3/mail/send")!
        var request = URLRequest(url: endpoint)
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
        ] as [String: Any]

        await sendSendGridEmail(request: &request, body: body)
    }

    private func deliverDigestViaEmail(target: DeliveryTarget, report: DigestReport) async {
        guard let apiKey = getSecretFromKeychain(service: "SLATE", account: "SendGridAPIKey") else {
            print("[NotificationService] SendGrid API key not found in Keychain")
            return
        }

        let endpoint = URL(string: "https://api.sendgrid.com/v3/mail/send")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let subject = "[SLATE] \(report.projectName) — Daily Digest \(report.date)"
        let plain = DigestService.plainTextEmailBody(for: report)
        let body = [
            "personalizations": [[
                "to": [["email": target.address]],
                "subject": subject
            ]],
            "from": ["email": "noreply@mountaintoppictures.com", "name": "SLATE"],
            "content": [[
                "type": "text/plain",
                "value": plain
            ]]
        ] as [String: Any]

        await sendSendGridEmail(request: &request, body: body)
    }

    private func sendSendGridEmail(request: inout URLRequest, body: [String: Any]) async {
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
        let webhook = URL(string: target.address)!
        var request = URLRequest(url: webhook)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = [
            "text": "[SLATE] *\(projectName)* dailies are ready. Review → \(url.absoluteString)"
        ] as [String: Any]

        await postSlackJSON(request: &request, body: body)
    }

    private func deliverDigestViaSlack(target: DeliveryTarget, report: DigestReport) async {
        guard let webhook = URL(string: target.address) else {
            return
        }
        var request = URLRequest(url: webhook)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let blocks = digestSlackBlocks(for: report)
        let body: [String: Any] = ["blocks": blocks]
        await postSlackJSON(request: &request, body: body)
    }

    private func digestSlackBlocks(for report: DigestReport) -> [[String: Any]] {
        let summary = "\(report.totalClipsIngested) clips ingested | \(String(format: "%.1f", report.totalDurationMinutes)) min | Avg score: \(String(format: "%.0f", report.averageCompositeScore))/100"

        func mdLines(title: String, lines: [String]) -> String {
            guard !lines.isEmpty else {
                return "*\(title)*\n_No entries_"
            }
            return "*\(title)*\n" + lines.joined(separator: "\n")
        }

        let topLines = report.topTakes.map { t in
            "• \(t.label) — \(String(format: "%.0f", t.compositeScore))/100 — \(t.reasonSummary)"
        }
        let flaggedLines = report.flaggedTakes.map { t in
            "• \(t.label) — \(String(format: "%.0f", t.compositeScore))/100 — \(t.reasonSummary)"
        }
        let coverage = """
        *Scene coverage*
        Completed: \(report.scenesCompleted.joined(separator: ", "))
        In progress: \(report.scenesContinued.joined(separator: ", "))
        """

        return [
            [
                "type": "header",
                "text": [
                    "type": "plain_text",
                    "text": ":clapper: SLATE Daily Digest — \(report.projectName)",
                    "emoji": true
                ] as [String: Any]
            ],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": summary
                ] as [String: Any]
            ],
            ["type": "divider"],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": mdLines(title: "Top takes", lines: topLines)
                ] as [String: Any]
            ],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": mdLines(title: "Flagged takes", lines: flaggedLines)
                ] as [String: Any]
            ],
            [
                "type": "section",
                "text": [
                    "type": "mrkdwn",
                    "text": coverage
                ] as [String: Any]
            ]
        ]
    }

    private func postSlackJSON(request: inout URLRequest, body: [String: Any]) async {
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
