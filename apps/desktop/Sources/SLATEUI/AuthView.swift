// SLATE — AuthView
// Owned by: Claude Code
//
// C4: Authentication gate shown before ContentView when Supabase is configured
// and the user is not yet signed in.
//
// Modes:
//  • Supabase configured, not authenticated  → email/password sign-in form
//  • Supabase not configured                 → offline banner + "Continue Offline" button
//
// Accessed via @EnvironmentObject SupabaseManager injected by SLATEApp.

import SwiftUI
import SLATECore

public struct AuthView: View {
    @EnvironmentObject private var supabaseManager: SupabaseManager

    @State private var email    = ""
    @State private var password = ""

    public init() {}

    public var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(white: 0.08), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo / wordmark
                VStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundColor(.white.opacity(0.9))
                    Text("SLATE")
                        .font(.system(size: 32, weight: .ultraLight, design: .rounded))
                        .tracking(8)
                        .foregroundColor(.white)
                    Text("Video Dailies Review")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                }
                .padding(.bottom, 48)

                // Auth card
                if supabaseManager.isConfigured {
                    SignInCard(email: $email, password: $password)
                } else {
                    OfflineCard()
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 480, minHeight: 520)
    }
}

// MARK: - Sign-In Card

private struct SignInCard: View {
    @EnvironmentObject private var supabaseManager: SupabaseManager
    @Binding var email: String
    @Binding var password: String

    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(spacing: 20) {

            // Title
            VStack(spacing: 4) {
                Text("Sign In")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                Text("Use your Supabase project credentials.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))
            }

            // Fields
            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .onSubmit { focusedField = .password }

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .onSubmit { Task { await signIn() } }
            }

            // Error
            if let error = supabaseManager.authError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
            }

            // Sign-in button
            Button {
                Task { await signIn() }
            } label: {
                if supabaseManager.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.75).colorScheme(.dark)
                        Text("Signing In…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text("Sign In")
                        .frame(maxWidth: .infinity)
                }
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(supabaseManager.isLoading || email.isEmpty || password.isEmpty)

            Divider().background(Color.white.opacity(0.1))

            // Google OAuth button
            Button {
                Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 16))
                    Text("Continue with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(supabaseManager.isLoading)
            .help("Sign in with your Google account")

            Divider().background(Color.white.opacity(0.1))

            // Offline escape hatch
            Button("Continue Offline") {
                // Posting this custom notification causes SLATEApp to treat the
                // user as bypassing auth — handled in the app's scene body.
                NotificationCenter.default.post(name: .continueOffline, object: nil)
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.45))
            .buttonStyle(.plain)

        }
        .padding(32)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08))
                )
        )
        .onAppear { focusedField = .email }
    }

    private func signIn() async {
        await supabaseManager.signIn(email: email, password: password)
    }
    
    private func signInWithGoogle() async {
        await supabaseManager.signInWithGoogle()
    }
}

// MARK: - Offline Card

private struct OfflineCard: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 36))
                .foregroundColor(.orange.opacity(0.8))

            VStack(spacing: 6) {
                Text("Supabase Not Configured")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("""
                     Set SLATE_SUPABASE_URL and SLATE_SUPABASE_ANON_KEY \
                     to enable cloud sync and review sharing.
                     """)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button("Continue Offline") {
                NotificationCenter.default.post(name: .continueOffline, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange.opacity(0.85))
        }
        .padding(32)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08))
                )
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    /// Posted by AuthView when the user chooses to bypass sign-in and run offline.
    public static let continueOffline = Notification.Name("continueOffline")
}
