// SLATE — ShareLinkSheet
// Owned by: Claude Code
//
// C3: Sheet for creating a share link for a project. Calls the
// generate-share-link edge function via ShareLinkService.
//
// Triggered by the Share toolbar button in ContentView when a project is
// selected. On success shows the review URL with a copy-to-clipboard action.
//
// C4: Reads the real Supabase Auth JWT from SupabaseManager instead of the
// placeholder string used in C3.

import AppKit
import SwiftUI
import SLATECore
import SLATESharedTypes

// MARK: - Main sheet

public struct ShareLinkSheet: View {
    let project: Project

    @EnvironmentObject private var supabaseManager: SupabaseManager

    @State private var scope: ShareLinkScope = .project
    @State private var expiryHours: Int = 168
    @State private var usePassword = false
    @State private var password = ""
    @State private var canComment = true
    @State private var canFlag = true
    @State private var canRequestAlternate = false
    @State private var isGenerating = false
    @State private var result: ShareLinkResult?
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    public init(project: Project) {
        self.project = project
    }

    public var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.accentColor)
                Text("Share \"\(project.name)\"")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // ── Body ─────────────────────────────────────────────────────────
            if let result {
                ShareLinkResultView(result: result) { dismiss() }
            } else {
                ShareLinkFormView(
                    project: project,
                    scope: $scope,
                    expiryHours: $expiryHours,
                    usePassword: $usePassword,
                    password: $password,
                    canComment: $canComment,
                    canFlag: $canFlag,
                    canRequestAlternate: $canRequestAlternate,
                    isGenerating: isGenerating,
                    errorMessage: errorMessage,
                    onCancel: { dismiss() },
                    onGenerate: { Task { await generate() } }
                )
            }
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func generate() async {
        isGenerating = true
        errorMessage = nil

        // C4: Use the live session token. Falls back to SLATE_DEBUG_JWT for local
        // testing without a full Supabase Auth flow.
        let jwt = supabaseManager.accessToken
            ?? ProcessInfo.processInfo.environment["SLATE_DEBUG_JWT"]
            ?? ""

        let permissions = ShareLinkPermissions(
            canComment: canComment,
            canFlag: canFlag,
            canRequestAlternate: canRequestAlternate
        )

        do {
            let r = try await ShareLinkService.shared.generateShareLink(
                projectId: project.id,
                scope: scope,
                expiryHours: expiryHours,
                password: usePassword && !password.isEmpty ? password : nil,
                permissions: permissions,
                jwt: jwt
            )
            result = r
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

// MARK: - Form

private struct ShareLinkFormView: View {
    let project: Project
    @Binding var scope: ShareLinkScope
    @Binding var expiryHours: Int
    @Binding var usePassword: Bool
    @Binding var password: String
    @Binding var canComment: Bool
    @Binding var canFlag: Bool
    @Binding var canRequestAlternate: Bool
    let isGenerating: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onGenerate: () -> Void

    private let expiryOptions: [(label: String, hours: Int)] = [
        ("24 hours", 24),
        ("3 days", 72),
        ("7 days", 168),
        ("14 days", 336),
        ("30 days", 720)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Scope
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scope")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $scope) {
                            ForEach(ShareLinkScope.allCases, id: \.self) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("Reviewers will see the \(scope.displayName.lowercased()) view.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Expiry
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Link Expiry")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Expires after", selection: $expiryHours) {
                            ForEach(expiryOptions, id: \.hours) { opt in
                                Text(opt.label).tag(opt.hours)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Password
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Password protect this link", isOn: $usePassword)
                            .font(.subheadline)
                        if usePassword {
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                // Permissions
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Reviewer Permissions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Toggle("Can add comments", isOn: $canComment)
                        Toggle("Can flag clips", isOn: $canFlag)
                        Toggle("Can request alternate takes", isOn: $canRequestAlternate)
                    }
                }

                // Error banner
                if let msg = errorMessage {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                }
            }
            .padding()
        }

        Divider()

        // Footer buttons
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape)
            Spacer()
            Button {
                onGenerate()
            } label: {
                if isGenerating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Generating…")
                    }
                    .frame(minWidth: 120)
                } else {
                    Text("Generate Link")
                        .frame(minWidth: 120)
                }
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating || (usePassword && password.isEmpty))
        }
        .padding()
    }
}

// MARK: - Result

private struct ShareLinkResultView: View {
    let result: ShareLinkResult
    let onDismiss: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Share Link Created")
                .font(.headline)

            Text("Send this link to your reviewers.")
                .foregroundColor(.secondary)
                .font(.subheadline)

            // URL row
            HStack(spacing: 8) {
                Text(result.url)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.url, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 24)
                }
                .buttonStyle(.bordered)
                .help(copied ? "Copied!" : "Copy to clipboard")
            }

            Text("Expires: \(result.expiresAt)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Button("Open in Browser") {
                    if let url = URL(string: result.url) {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
