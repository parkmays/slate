import SwiftUI

enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case welcome
    case selectProject
    case browseClips
    case clipDetail
    case shareReview
    case shortcuts

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to SLATE"
        case .selectProject:
            return "Select or Create a Project"
        case .browseClips:
            return "Browse and Filter Dailies"
        case .clipDetail:
            return "Inspect Clip Details"
        case .shareReview:
            return "Share and Review"
        case .shortcuts:
            return "Presenter Shortcuts"
        }
    }

    var message: String {
        switch self {
        case .welcome:
            return "This guided walkthrough helps you run the prototype demo flow quickly."
        case .selectProject:
            return "Use the sidebar to pick a project or the + toolbar button to create one."
        case .browseClips:
            return "Use search, filters, and view toggles to surface the right take fast."
        case .clipDetail:
            return "Open a clip to preview proxy, sync confidence, AI signals, and notes."
        case .shareReview:
            return "Use Share Project to open reviewer-ready flows. Local demo mode still works offline."
        case .shortcuts:
            return "Use Command+Shift+W to replay this tour and toolbar hints for action shortcuts."
        }
    }
}

struct WalkthroughOverlayCard: View {
    let step: WalkthroughStep
    let totalSteps: Int
    let onNext: () -> Void
    let onSkip: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Prototype Walkthrough")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(step.title)
                .font(.headline)
            Text(step.message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Text("Step \(step.rawValue + 1) of \(totalSteps)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Skip", action: onSkip)
                    .keyboardShortcut(.escape)
                if step.rawValue + 1 < totalSteps {
                    Button("Next", action: onNext)
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Done", action: onDone)
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor.opacity(0.25))
        )
    }
}

enum ToolbarActionID: String, CaseIterable, Codable, Identifiable {
    case ingest
    case share
    case assembly
    case cloudSync
    case productionSync
    case color
    case newProject

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ingest: return "Ingest Progress"
        case .share: return "Share Project"
        case .assembly: return "Assembly Workspace"
        case .cloudSync: return "Cloud Sync"
        case .productionSync: return "Production Sync"
        case .color: return "Color / LUT"
        case .newProject: return "New Project"
        }
    }
}

struct ToolbarCustomizationStore {
    private static let key = "SLATE.toolbar.customization.v1"

    static let defaultActions: [ToolbarActionID] = [
        .ingest,
        .share,
        .assembly,
        .cloudSync,
        .productionSync,
        .color,
        .newProject,
    ]

    static func load() -> [ToolbarActionID] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ToolbarActionID].self, from: data),
              !decoded.isEmpty
        else {
            return defaultActions
        }
        return decoded
    }

    static func save(_ actions: [ToolbarActionID]) {
        guard !actions.isEmpty,
              let encoded = try? JSONEncoder().encode(actions)
        else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }
}

struct ToolbarCustomizationSheet: View {
    @Binding var actions: [ToolbarActionID]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize Toolbar")
                .font(.headline)
            Text("Reorder toolbar actions for your meeting flow.")
                .font(.caption)
                .foregroundColor(.secondary)

            List {
                ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                    HStack {
                        Text(action.label)
                        Spacer()
                        Button {
                            moveUp(index: index)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            moveDown(index: index)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == actions.count - 1)
                    }
                }
            }
            .frame(minHeight: 210)

            HStack {
                Menu("Add Action") {
                    ForEach(ToolbarActionID.allCases.filter { !actions.contains($0) }) { action in
                        Button(action.label) {
                            actions.append(action)
                        }
                    }
                }
                .disabled(actions.count == ToolbarActionID.allCases.count)

                Button("Reset") {
                    actions = ToolbarCustomizationStore.defaultActions
                }

                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 460, height: 360)
    }

    private func moveUp(index: Int) {
        guard index > 0 else { return }
        actions.swapAt(index, index - 1)
    }

    private func moveDown(index: Int) {
        guard index < actions.count - 1 else { return }
        actions.swapAt(index, index + 1)
    }
}
