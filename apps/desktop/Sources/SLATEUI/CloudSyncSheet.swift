import AppKit
import SwiftUI
import SLATECore
import SLATESharedTypes

public struct CloudSyncSheet: View {
    let project: Project
    @ObservedObject var clipStore: GRDBClipStore
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var cloudSyncStore: CloudSyncStore
    @ObservedObject var cloudAuthManager: CloudAuthManager

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDestinationId: String?
    @State private var provider: CloudSyncProvider = .googleDrive
    @State private var destinationName = "Google Drive Dailies"
    @State private var remotePath = "/Apps/SLATE"
    @State private var remoteFolderId = ""
    @State private var accountId = ""
    @State private var includeFootage = true
    @State private var includeEdit = true
    @State private var includeComments = true
    @State private var oauthClientId = ""
    @State private var oauthClientSecret = ""
    @State private var notice: CloudSyncNotice?

    public init(
        project: Project,
        clipStore: GRDBClipStore,
        projectStore: ProjectStore,
        cloudSyncStore: CloudSyncStore,
        cloudAuthManager: CloudAuthManager
    ) {
        self.project = project
        self.clipStore = clipStore
        self.projectStore = projectStore
        self.cloudSyncStore = cloudSyncStore
        self.cloudAuthManager = cloudAuthManager
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            HStack(spacing: 0) {
                destinationSidebar
                    .frame(width: 280)

                Divider()

                detailPane
            }
        }
        .frame(minWidth: 980, minHeight: 680)
        .task(id: project.id) {
            await cloudSyncStore.load(project: project)
            refreshDestinationSelection()
            loadProviderConfiguration(for: provider)
        }
        .onChange(of: cloudSyncStore.destinations.map(\.id)) {
            refreshDestinationSelection()
        }
        .onChange(of: provider) {
            applyProviderDefaultsIfNeeded(for: provider)
            loadProviderConfiguration(for: provider)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Cloud Sync", systemImage: "icloud.and.arrow.up")
                    .font(.headline)

                Text("Connect Google Drive, Dropbox, or Frame.io in-app, then push or pull footage, assembly exports, and review comments while keeping a local sync history for the project.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 620, alignment: .leading)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(20)
    }

    private var destinationSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            CloudSyncSummaryCard(
                destinationCount: cloudSyncStore.destinations.count,
                syncedRecordCount: cloudSyncStore.records.filter { $0.status == .synced }.count,
                failedRecordCount: cloudSyncStore.records.filter { $0.status == .failed }.count,
                lastSyncedAt: cloudSyncStore.records.first?.syncedAt
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Destinations")
                    .font(.subheadline.weight(.semibold))

                if cloudSyncStore.loading {
                    ProgressView("Loading destinations…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if cloudSyncStore.destinations.isEmpty {
                    CloudSyncEmptyStateCard(
                        title: "No destinations yet",
                        message: "Create a provider target to start pushing footage, edit packages, and comment manifests into the cloud."
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(cloudSyncStore.destinations) { destination in
                                CloudSyncDestinationCard(
                                    destination: destination,
                                    isSelected: destination.id == selectedDestinationId,
                                    isReady: isProviderReady(for: destination.provider),
                                    select: {
                                        selectedDestinationId = destination.id
                                        notice = nil
                                    },
                                    delete: {
                                        Task {
                                            await delete(destination)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Spacer()

            CloudSyncEmptyStateCard(
                title: "Provider access",
                message: "Connect providers with OAuth in this sheet, or keep using environment-token fallbacks like \(provider.tokenEnvironmentVariable) when you need a headless setup."
            )
        }
        .padding(20)
    }

    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                syncOptionsCard

                if let notice {
                    CloudSyncNoticeBanner(notice: notice)
                }

                if let errorMessage = cloudSyncStore.errorMessage, notice == nil {
                    CloudSyncNoticeBanner(
                        notice: CloudSyncNotice(
                            title: "Sync issue",
                            message: errorMessage,
                            style: .error
                        )
                    )
                }

                selectedDestinationCard
                providerConnectionCard
                destinationFormCard
                syncHistoryCard
            }
            .padding(20)
        }
    }

    private var syncOptionsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Scope")
                        .font(.headline)
                    Text("Choose which project artifacts move to the selected destination.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if cloudSyncStore.isSyncing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            VStack(spacing: 10) {
                CloudSyncOptionRow(
                    title: "Footage",
                    subtitle: "Upload original source media from the project library.",
                    countLabel: "\(clipStore.clips.count) clip\(clipStore.clips.count == 1 ? "" : "s")",
                    isOn: $includeFootage
                )
                CloudSyncOptionRow(
                    title: "Edits",
                    subtitle: "Export the latest assembly archive so remote collaborators get the current cut package.",
                    countLabel: "Latest assembly snapshot",
                    isOn: $includeEdit
                )
                CloudSyncOptionRow(
                    title: "Comments",
                    subtitle: "Publish a review manifest with clip annotations, statuses, and assembly metadata.",
                    countLabel: "\(annotationCount) comment\(annotationCount == 1 ? "" : "s")",
                    isOn: $includeComments
                )
            }
        }
        .padding(18)
        .background(CloudSyncPanelBackground())
    }

    @ViewBuilder
    private var selectedDestinationCard: some View {
        if let destination = selectedDestination {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(destination.name, systemImage: destination.provider.iconName)
                            .font(.headline)
                        Text(destination.provider.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    CloudSyncAccessBadge(
                        title: providerAccessLabel(for: destination.provider),
                        isReady: isProviderReady(for: destination.provider)
                    )
                }

                CloudSyncDestinationMetadata(destination: destination)

                HStack(alignment: .top, spacing: 12) {
                    Button {
                        Task {
                            await sync(destination)
                        }
                    } label: {
                        Label(cloudSyncStore.isSyncing ? "Syncing…" : "Push Now", systemImage: "arrow.up.circle.fill")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cloudSyncStore.isSyncing || !hasSyncSelection || !isProviderReady(for: destination.provider))

                    Button {
                        Task {
                            await pull(destination)
                        }
                    } label: {
                        Label(cloudSyncStore.isSyncing ? "Syncing…" : "Pull From Cloud", systemImage: "arrow.down.circle")
                            .frame(minWidth: 140)
                    }
                    .buttonStyle(.bordered)
                    .disabled(cloudSyncStore.isSyncing || !hasSyncSelection || !isProviderReady(for: destination.provider))

                    Text("Push uploads the selected artifacts. Pull downloads the latest remote manifests, edits, and any missing footage for this project.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !isProviderReady(for: destination.provider) {
                    CloudSyncNoticeBanner(
                        notice: CloudSyncNotice(
                            title: "Provider connection required",
                            message: "Connect \(destination.provider.displayName) below or set \(destination.provider.tokenEnvironmentVariable) as an environment token before pushing or pulling this destination.",
                            style: .warning
                        )
                    )
                }
            }
            .padding(18)
            .background(CloudSyncPanelBackground())
        } else {
            CloudSyncEmptyStateCard(
                title: "Select a destination",
                message: "Pick an existing destination from the left or create a new one below. Once selected, you can sync footage, edit packages, and comments in one pass."
            )
        }
    }

    private var destinationFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Destination")
                .font(.headline)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("Provider", selection: $provider) {
                        ForEach(CloudSyncProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Destination name", text: $destinationName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            providerConfigurationFields

            HStack(alignment: .top) {
                CloudSyncAccessBadge(
                    title: providerAccessLabel(for: provider),
                    isReady: isProviderReady(for: provider)
                )

                Spacer()

                Button {
                    Task {
                        await saveDestination()
                    }
                } label: {
                    Label("Save Destination", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .background(CloudSyncPanelBackground())
    }

    private var providerConnectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider Connection")
                        .font(.headline)
                    Text("Store OAuth app settings once, then connect or disconnect \(provider.displayName) without leaving the app.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                CloudSyncAccessBadge(
                    title: providerAccessLabel(for: provider),
                    isReady: isProviderReady(for: provider)
                )
            }

            if let account = cloudAuthManager.account(for: provider) {
                CloudSyncConnectedAccountRow(account: account)
            } else if cloudAuthManager.hasEnvironmentToken(for: provider) {
                CloudSyncEmptyStateCard(
                    title: "Environment token active",
                    message: "\(provider.displayName) is currently available through \(provider.tokenEnvironmentVariable). OAuth is optional unless you want refreshable in-app auth."
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(oauthClientLabel(for: provider))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(oauthClientPlaceholder(for: provider), text: $oauthClientId)
                        .textFieldStyle(.roundedBorder)
                }

                if providerRequiresClientSecret(provider) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Client Secret")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SecureField(oauthClientSecretPlaceholder(for: provider), text: $oauthClientSecret)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Text(providerAuthHint(for: provider))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    saveProviderConfiguration()
                } label: {
                    Label("Save App Settings", systemImage: "externaldrive.badge.person.crop")
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await connectProvider()
                    }
                } label: {
                    Label(
                        cloudAuthManager.connectingProvider == provider ? "Connecting…" : "Connect",
                        systemImage: "person.crop.circle.badge.checkmark"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(cloudAuthManager.connectingProvider != nil || oauthClientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    disconnectProvider()
                } label: {
                    Label("Disconnect", systemImage: "person.crop.circle.badge.minus")
                }
                .buttonStyle(.bordered)
                .disabled(!isOAuthConnected(for: provider))
            }
        }
        .padding(18)
        .background(CloudSyncPanelBackground())
    }

    @ViewBuilder
    private var providerConfigurationFields: some View {
        switch provider {
        case .googleDrive:
            VStack(alignment: .leading, spacing: 6) {
                Text("Google Drive Folder ID")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Drive folder ID", text: $remoteFolderId)
                    .textFieldStyle(.roundedBorder)
                Text("Use the folder ID from the Drive URL. Files are uploaded into that folder with resumable upload support.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

        case .dropbox:
            VStack(alignment: .leading, spacing: 6) {
                Text("Dropbox Folder Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("/Apps/SLATE/ProjectName", text: $remotePath)
                    .textFieldStyle(.roundedBorder)
                Text("SLATE will create any missing Dropbox folders on the way down this path before uploading.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

        case .frameIO:
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame.io Account ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Account ID", text: $accountId)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame.io Folder ID")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Folder ID", text: $remoteFolderId)
                        .textFieldStyle(.roundedBorder)
                }

                Text("SLATE uploads through Frame.io’s local upload flow and tracks the returned asset URL in the project sync log.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var syncHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Sync History")
                    .font(.headline)
                Spacer()
                if let selectedDestination {
                    Text(selectedDestination.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            let records = displayedRecords
            if records.isEmpty {
                CloudSyncEmptyStateCard(
                    title: "No sync records yet",
                    message: "Run a sync and SLATE will keep a local record of each uploaded asset, its status, and any remote link returned by the provider."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(records.prefix(20)) { record in
                        CloudSyncRecordRow(record: record)
                    }
                }
            }
        }
        .padding(18)
        .background(CloudSyncPanelBackground())
    }

    private var selectedDestination: CloudSyncDestination? {
        guard let selectedDestinationId else {
            return cloudSyncStore.destinations.first
        }

        return cloudSyncStore.destinations.first(where: { $0.id == selectedDestinationId })
    }

    private var displayedRecords: [CloudSyncRecord] {
        guard let selectedDestination else {
            return cloudSyncStore.records
        }

        return cloudSyncStore.records.filter { $0.destinationId == selectedDestination.id }
    }

    private var hasSyncSelection: Bool {
        includeFootage || includeEdit || includeComments
    }

    private var annotationCount: Int {
        clipStore.clips.reduce(into: 0) { count, clip in
            count += clip.annotations.count
        }
    }

    private func refreshDestinationSelection() {
        if let selectedDestinationId,
           cloudSyncStore.destinations.contains(where: { $0.id == selectedDestinationId }) {
            return
        }

        selectedDestinationId = cloudSyncStore.destinations.first?.id
    }

    private func applyProviderDefaultsIfNeeded(for provider: CloudSyncProvider) {
        if destinationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || CloudSyncProvider.allCases.contains(where: { "\($0.displayName) Dailies" == destinationName }) {
            destinationName = "\(provider.displayName) Dailies"
        }

        if provider == .dropbox, remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            remotePath = "/Apps/SLATE/\(sanitizedProjectName)"
        }

        if provider == .frameIO,
           accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let connectedAccountId = cloudAuthManager.account(for: .frameIO)?.accountId {
            accountId = connectedAccountId
        }
    }

    private func saveDestination() async {
        notice = nil

        do {
            let resolvedAccountId: String
            if provider == .frameIO,
               accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let connectedAccountId = cloudAuthManager.account(for: .frameIO)?.accountId {
                resolvedAccountId = connectedAccountId
            } else {
                resolvedAccountId = accountId
            }

            let configuration = CloudSyncDestinationConfiguration(
                remotePath: remotePath,
                remoteFolderId: remoteFolderId,
                accountId: resolvedAccountId
            )
            try await cloudSyncStore.saveDestination(
                name: destinationName,
                provider: provider,
                configuration: configuration,
                project: project
            )
            refreshDestinationSelection()
            selectedDestinationId = cloudSyncStore.destinations.first?.id
            notice = CloudSyncNotice(
                title: "Destination saved",
                message: "\(provider.displayName) is ready for \(project.name).",
                style: .success
            )
            resetDraft()
        } catch {
            notice = CloudSyncNotice(
                title: "Could not save destination",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func sync(_ destination: CloudSyncDestination) async {
        notice = nil

        do {
            let summary = try await cloudSyncStore.sync(
                project: project,
                clips: clipStore.clips,
                destination: destination,
                options: CloudSyncOptions(
                    includeFootage: includeFootage,
                    includeEdit: includeEdit,
                    includeComments: includeComments
                ),
                authManager: cloudAuthManager
            )

            if summary.failedCount == 0 {
                notice = CloudSyncNotice(
                    title: "Sync complete",
                    message: "Uploaded \(summary.uploadedCount) item\(summary.uploadedCount == 1 ? "" : "s") to \(destination.name).",
                    style: .success
                )
            } else {
                let failureSummary = summary.failures
                    .prefix(2)
                    .map { "\($0.assetLabel): \($0.message)" }
                    .joined(separator: "\n")
                notice = CloudSyncNotice(
                    title: "Sync finished with issues",
                    message: "Uploaded \(summary.uploadedCount) item\(summary.uploadedCount == 1 ? "" : "s"), but \(summary.failedCount) failed.\n\(failureSummary)",
                    style: .warning
                )
            }
        } catch {
            notice = CloudSyncNotice(
                title: "Sync failed",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func pull(_ destination: CloudSyncDestination) async {
        notice = nil

        do {
            let summary = try await cloudSyncStore.pull(
                project: project,
                clips: clipStore.clips,
                destination: destination,
                options: CloudSyncOptions(
                    includeFootage: includeFootage,
                    includeEdit: includeEdit,
                    includeComments: includeComments
                ),
                projectStore: projectStore,
                authManager: cloudAuthManager
            )
            await clipStore.reloadCurrentProject()

            if summary.failedCount == 0 {
                notice = CloudSyncNotice(
                    title: "Cloud pull complete",
                    message: "Downloaded \(summary.downloadedCount) remote item\(summary.downloadedCount == 1 ? "" : "s"), imported \(summary.importedFootageCount) footage clip\(summary.importedFootageCount == 1 ? "" : "s"), merged \(summary.mergedClipCount) clip record\(summary.mergedClipCount == 1 ? "" : "s"), and refreshed \(summary.updatedAssemblyCount) assembly.",
                    style: .success
                )
            } else {
                let failureSummary = summary.failures
                    .prefix(2)
                    .map { "\($0.assetLabel): \($0.message)" }
                    .joined(separator: "\n")
                notice = CloudSyncNotice(
                    title: "Cloud pull finished with issues",
                    message: "Downloaded \(summary.downloadedCount) remote item\(summary.downloadedCount == 1 ? "" : "s"), but \(summary.failedCount) failed.\n\(failureSummary)",
                    style: .warning
                )
            }
        } catch {
            notice = CloudSyncNotice(
                title: "Cloud pull failed",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func delete(_ destination: CloudSyncDestination) async {
        notice = nil

        do {
            try await cloudSyncStore.deleteDestination(destination)
            if selectedDestinationId == destination.id {
                selectedDestinationId = cloudSyncStore.destinations.first?.id
            }
            notice = CloudSyncNotice(
                title: "Destination removed",
                message: "Deleted \(destination.name) and its local sync records.",
                style: .success
            )
        } catch {
            notice = CloudSyncNotice(
                title: "Could not delete destination",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func loadProviderConfiguration(for provider: CloudSyncProvider) {
        let configuration = cloudAuthManager.configuration(for: provider)
        oauthClientId = configuration.clientId
        oauthClientSecret = configuration.clientSecret ?? ""
    }

    private func saveProviderConfiguration() {
        cloudAuthManager.saveConfiguration(
            for: provider,
            clientId: oauthClientId,
            clientSecret: providerRequiresClientSecret(provider) ? oauthClientSecret : nil
        )
        notice = CloudSyncNotice(
            title: "App settings saved",
            message: "\(provider.displayName) OAuth settings are stored locally, and environment-token fallbacks still work when you need headless automation.",
            style: .success
        )
    }

    private func connectProvider() async {
        notice = nil
        saveProviderConfiguration()

        do {
            try await cloudAuthManager.connect(provider: provider)
            if provider == .frameIO,
               accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let connectedAccountId = cloudAuthManager.account(for: .frameIO)?.accountId {
                accountId = connectedAccountId
            }
            notice = CloudSyncNotice(
                title: "Provider connected",
                message: "\(provider.displayName) is ready for project sync.",
                style: .success
            )
        } catch {
            notice = CloudSyncNotice(
                title: "Connection failed",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func disconnectProvider() {
        do {
            try cloudAuthManager.disconnect(provider: provider)
            notice = CloudSyncNotice(
                title: "Provider disconnected",
                message: "\(provider.displayName) was removed from the local keychain.",
                style: .success
            )
        } catch {
            notice = CloudSyncNotice(
                title: "Disconnect failed",
                message: error.localizedDescription,
                style: .error
            )
        }
    }

    private func isProviderReady(for provider: CloudSyncProvider) -> Bool {
        cloudAuthManager.hasConnectedAccount(for: provider)
    }

    private func isOAuthConnected(for provider: CloudSyncProvider) -> Bool {
        cloudAuthManager.account(for: provider) != nil
    }

    private func providerAccessLabel(for provider: CloudSyncProvider) -> String {
        if let account = cloudAuthManager.account(for: provider) {
            return account.email ?? account.displayName
        }

        if cloudAuthManager.hasEnvironmentToken(for: provider) {
            return provider.tokenEnvironmentVariable
        }

        return "Not Connected"
    }

    private func oauthClientLabel(for provider: CloudSyncProvider) -> String {
        switch provider {
        case .googleDrive:
            return "OAuth Client ID"
        case .dropbox:
            return "App Key"
        case .frameIO:
            return "Client ID"
        }
    }

    private func oauthClientPlaceholder(for provider: CloudSyncProvider) -> String {
        switch provider {
        case .googleDrive:
            return "Google desktop OAuth client ID"
        case .dropbox:
            return "Dropbox app key"
        case .frameIO:
            return "Adobe Developer client ID"
        }
    }

    private func oauthClientSecretPlaceholder(for provider: CloudSyncProvider) -> String {
        switch provider {
        case .googleDrive:
            return ""
        case .dropbox:
            return "Dropbox app secret"
        case .frameIO:
            return "Adobe Developer client secret"
        }
    }

    private func providerRequiresClientSecret(_ provider: CloudSyncProvider) -> Bool {
        switch provider {
        case .googleDrive:
            return false
        case .dropbox, .frameIO:
            return true
        }
    }

    private func providerAuthHint(for provider: CloudSyncProvider) -> String {
        switch provider {
        case .googleDrive:
            return "Google Drive uses a desktop OAuth client. The client ID can also come from SLATE_GOOGLE_DRIVE_CLIENT_ID if you prefer environment-based config."
        case .dropbox:
            return "Dropbox uses an app key and secret with offline access so SLATE can refresh tokens locally. Environment fallbacks: SLATE_DROPBOX_APP_KEY and SLATE_DROPBOX_APP_SECRET."
        case .frameIO:
            return "Frame.io uses Adobe OAuth credentials and stores refresh tokens in the macOS keychain. Environment fallbacks: SLATE_FRAMEIO_CLIENT_ID and SLATE_FRAMEIO_CLIENT_SECRET."
        }
    }

    private var sanitizedProjectName: String {
        let replaced = project.name.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        return replaced.isEmpty ? "SLATE" : replaced
    }

    private func resetDraft() {
        destinationName = "\(provider.displayName) Dailies"
        switch provider {
        case .googleDrive:
            remoteFolderId = ""
        case .dropbox:
            remotePath = "/Apps/SLATE/\(sanitizedProjectName)"
        case .frameIO:
            accountId = ""
            remoteFolderId = ""
        }
    }
}

private struct CloudSyncSummaryCard: View {
    let destinationCount: Int
    let syncedRecordCount: Int
    let failedRecordCount: Int
    let lastSyncedAt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Summary")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 10) {
                CloudSyncMetricChip(value: "\(destinationCount)", label: "Destinations")
                CloudSyncMetricChip(value: "\(syncedRecordCount)", label: "Uploaded")
                CloudSyncMetricChip(value: "\(failedRecordCount)", label: "Failed")
            }

            if let lastSyncedAt {
                Text("Last sync: \(lastSyncedAt)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No syncs yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(CloudSyncPanelBackground())
    }
}

private struct CloudSyncMetricChip: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct CloudSyncDestinationCard: View {
    let destination: CloudSyncDestination
    let isSelected: Bool
    let isReady: Bool
    let select: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: select) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: destination.provider.iconName)
                        .foregroundColor(.accentColor)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(destination.provider.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack {
                CloudSyncAccessBadge(
                    title: isReady ? "Connected" : "Needs Access",
                    isReady: isReady
                )
                Spacer()
                Button(role: .destructive, action: delete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete destination")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.12))
                )
        )
    }
}

private struct CloudSyncDestinationMetadata: View {
    let destination: CloudSyncDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let remoteFolderId = destination.configuration.remoteFolderId, !remoteFolderId.isEmpty {
                CloudSyncMetadataRow(label: "Folder ID", value: remoteFolderId)
            }
            if let remotePath = destination.configuration.remotePath, !remotePath.isEmpty {
                CloudSyncMetadataRow(label: "Path", value: remotePath)
            }
            if let accountId = destination.configuration.accountId, !accountId.isEmpty {
                CloudSyncMetadataRow(label: "Account", value: accountId)
            }
            CloudSyncMetadataRow(label: "Updated", value: destination.updatedAt)
        }
    }
}

private struct CloudSyncMetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

private struct CloudSyncOptionRow: View {
    let title: String
    let subtitle: String
    let countLabel: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(countLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

private struct CloudSyncRecordRow: View {
    let record: CloudSyncRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .foregroundColor(record.status == .synced ? .accentColor : .orange)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(record.assetLabel)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        statusBadge
                    }

                    Text("\(record.assetKind.displayName) • \(record.provider.displayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let remotePath = record.remotePath, !remotePath.isEmpty {
                        Text(remotePath)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    Text(record.syncedAt)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Reveal Local") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.localPath)])
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if let remoteURL = record.remoteURL, let url = URL(string: remoteURL) {
                    Link("Open Remote", destination: url)
                        .font(.caption)
                }

                if let errorMessage = record.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private var iconName: String {
        switch record.assetKind {
        case .footage:
            return "film"
        case .edit:
            return "timeline.selection"
        case .comments:
            return "text.bubble"
        }
    }

    private var statusBadge: some View {
        Text(record.status == .synced ? "Synced" : "Failed")
            .font(.caption.weight(.semibold))
            .foregroundColor(record.status == .synced ? .green : .orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((record.status == .synced ? Color.green : Color.orange).opacity(0.14))
            )
    }
}

private struct CloudSyncAccessBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isReady ? "checkmark.shield.fill" : "key.slash")
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
        .foregroundColor(isReady ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill((isReady ? Color.green : Color.orange).opacity(0.12))
        )
        .textSelection(.enabled)
    }
}

private struct CloudSyncConnectedAccountRow: View {
    let account: CloudProviderAccount

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundColor(.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))

                if let email = account.email, !email.isEmpty {
                    Text(email)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    if let accountId = account.accountId, !accountId.isEmpty {
                        Text(accountId)
                            .font(.caption2.monospaced())
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if let expiresAt = account.expiresAt, !expiresAt.isEmpty {
                        Text("Expires \(expiresAt)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.05))
        )
    }
}

private struct CloudSyncEmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(CloudSyncPanelBackground())
    }
}

private struct CloudSyncNotice: Equatable {
    enum Style: Equatable {
        case success
        case warning
        case error

        var tint: Color {
            switch self {
            case .success:
                return .green
            case .warning:
                return .orange
            case .error:
                return .red
            }
        }

        var iconName: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .warning:
                return "exclamationmark.triangle.fill"
            case .error:
                return "xmark.octagon.fill"
            }
        }
    }

    let title: String
    let message: String
    let style: Style
}

private struct CloudSyncNoticeBanner: View {
    let notice: CloudSyncNotice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.style.iconName)
                .foregroundColor(notice.style.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                Text(notice.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(notice.style.tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(notice.style.tint.opacity(0.22))
                )
        )
    }
}

private struct CloudSyncPanelBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.secondary.opacity(0.14))
            )
            .shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
}
