// SLATE — CustomizableToolbar
// Owned by: Claude Code
//
// Enhanced toolbar with drag-and-drop customization, configurable actions,
// and support for user-defined toolbar layouts.

import SwiftUI
import SLATECore
import SLATESharedTypes

struct CustomizableToolbar: View {
    @Binding var actions: [ToolbarAction]
    @State private var isEditing = false
    @State private var draggedItem: ToolbarAction?
    @State private var showingCustomizationSheet = false
    @State private var availableActions: [ToolbarAction] = ToolbarAction.defaultActions
    
    let onAction: (ToolbarAction) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            // Toolbar actions
            ForEach(actions) { action in
                ToolbarButton(
                    action: action,
                    isEditing: isEditing,
                    onAction: onAction,
                    onRemove: { removeAction(action) }
                )
            }
            
            // Add button when editing
            if isEditing {
                Menu {
                    ForEach(availableActions.filter { !actions.contains($0) }) { action in
                        Button {
                            addAction(action)
                        } label: {
                            Label(action.title, systemImage: action.icon)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .tooltip("Add toolbar item")
            }
            
            Spacer()
            
            // Edit/Done button
            Button {
                withAnimation {
                    isEditing.toggle()
                }
            } label: {
                Image(systemName: isEditing ? "checkmark" : "pencil")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
            .tooltip(isEditing ? "Done editing" : "Customize toolbar", shortcut: "t", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
    
    private func addAction(_ action: ToolbarAction) {
        if !actions.contains(action) {
            actions.append(action)
        }
    }
    
    private func removeAction(_ action: ToolbarAction) {
        actions.removeAll { $0.id == action.id }
    }
}

// MARK: - Toolbar Button

struct ToolbarButton: View {
    let action: ToolbarAction
    let isEditing: Bool
    let onAction: (ToolbarAction) -> Void
    let onRemove: () -> Void
    
    var body: some View {
        Button {
            if isEditing {
                onRemove()
            } else {
                onAction(action)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: action.icon)
                    .font(.system(size: 14, weight: .medium))
                
                if action.showLabel {
                    Text(action.title)
                        .font(.caption)
                }
            }
            .foregroundColor(isEditing ? .red : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEditing ? Color.red.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.borderless)
        .tooltip(action.tooltip, shortcut: action.shortcut, modifiers: action.modifiers)
        .opacity(isEditing ? 0.7 : 1.0)
        .scaleEffect(isEditing ? 0.9 : 1.0)
    }
}

// MARK: - Toolbar Action

struct ToolbarAction: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let icon: String
    let shortcut: KeyEquivalent?
    let modifiers: EventModifiers
    let showLabel: Bool
    let tooltip: String
    let handler: () -> Void
    
    static let defaultActions: [ToolbarAction] = [
        ToolbarAction(
            title: "New Project",
            icon: "plus.square",
            shortcut: "n",
            modifiers: .command,
            showLabel: true,
            tooltip: "Create a new project"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Import",
            icon: "square.and.arrow.down",
            shortcut: "i",
            modifiers: .command,
            showLabel: true,
            tooltip: "Import media files"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Filter",
            icon: "line.horizontal.3.decrease.circle",
            shortcut: "f",
            modifiers: .command,
            showLabel: true,
            tooltip: "Filter clips"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Search",
            icon: "magnifyingglass",
            shortcut: "k",
            modifiers: .command,
            showLabel: false,
            tooltip: "Search clips"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Ingest",
            icon: "arrow.down.circle",
            shortcut: "i",
            modifiers: [.command, .shift],
            showLabel: true,
            tooltip: "Show ingest progress"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Walkthrough",
            icon: "play.circle",
            shortcut: "w",
            modifiers: [.command, .shift],
            showLabel: true,
            tooltip: "Start walkthrough"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Settings",
            icon: "gear",
            shortcut: ",",
            modifiers: .command,
            showLabel: false,
            tooltip: "Open settings"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Sync",
            icon: "arrow.triangle.2.circlepath",
            shortcut: nil,
            modifiers: [],
            showLabel: false,
            tooltip: "Sync with cloud"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Share",
            icon: "square.and.arrow.up",
            shortcut: nil,
            modifiers: [],
            showLabel: false,
            tooltip: "Share project"
        ) { /* Handled by parent */ },
        
        ToolbarAction(
            title: "Export",
            icon: "square.and.arrow.up",
            shortcut: "e",
            modifiers: .command,
            showLabel: true,
            tooltip: "Export project"
        ) { /* Handled by parent */ }
    ]
    
    static func == (lhs: ToolbarAction, rhs: ToolbarAction) -> Bool {
        lhs.id == rhs.id
    }
}


// MARK: - Enhanced Clip Grid View Toolbar

struct EnhancedClipGridViewToolbar: View {
    @Binding var viewMode: ViewMode
    @Binding var sortBy: SortOption
    @Binding var sortOrder: SortOrder
    @Binding var searchText: String
    @Binding var filterStatus: ReviewStatus?
    @Binding var showingFilterMenu: Bool
    @Binding var showingIngestProgress: Bool
    @Binding var showingSettings: Bool
    @Binding var showingWalkthrough: Bool
    @State private var toolbarActions: [ToolbarAction] = []
    
    let clipCount: Int
    let searchPrompt: String
    let hasActiveFilters: Bool
    let clearFilters: () -> Void
    let onNewProject: () -> Void
    let onImport: () -> Void
    let onShare: () -> Void
    let onExport: () -> Void
    let onSync: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Main toolbar
            CustomizableToolbar(actions: $toolbarActions) { action in
                handleToolbarAction(action)
            }
            
            Divider()
            
            // Secondary toolbar with view controls
            HStack(spacing: 12) {
                // View mode toggle
                Picker("View", selection: $viewMode) {
                    Image(systemName: "square.grid.2x2")
                        .tag(ViewMode.grid)
                    Image(systemName: "list.bullet")
                        .tag(ViewMode.list)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .tooltip("Toggle grid/list clip view", shortcut: "1")
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                    
                    TextField(searchPrompt, text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(maxWidth: 200)
                .tooltip("Search clips and metadata", shortcut: "k", modifiers: .command)
                
                Spacer()
                
                // Filter button
                Button {
                    showingFilterMenu.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.horizontal.3.decrease.circle")
                        Text("Filter")
                        if filterStatus != nil {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .popover(isPresented: $showingFilterMenu) {
                    FilterMenu(
                        selectedStatus: $filterStatus,
                        onClear: {
                            filterStatus = nil
                            showingFilterMenu = false
                        }
                    )
                    .frame(width: 200)
                }
                .tooltip("Filter clips by review status", shortcut: "f", modifiers: .command)
                
                // Sort menu
                Menu {
                    Menu("Sort by") {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Button {
                                sortBy = option
                            } label: {
                                Label(option.displayName, systemImage: sortBy == option ? "checkmark" : "")
                            }
                        }
                    }
                    
                    Menu("Order") {
                        Button {
                            sortOrder = .ascending
                        } label: {
                            Label("Ascending", systemImage: sortOrder == .ascending ? "checkmark" : "")
                        }
                        Button {
                            sortOrder = .descending
                        } label: {
                            Label("Descending", systemImage: sortOrder == .descending ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text("Sort")
                    }
                }
                .tooltip("Sort visible clips")
                
                if hasActiveFilters {
                    Button("Clear", action: clearFilters)
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .tooltip("Clear active search and status filters")
                }
                
                // Clip count
                Text("\(clipCount) clips")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear {
            setupDefaultToolbar()
        }
    }
    
    private func handleToolbarAction(_ action: ToolbarAction) {
        switch action.title {
        case "New Project":
            onNewProject()
        case "Import":
            onImport()
        case "Filter":
            showingFilterMenu.toggle()
        case "Search":
            // Focus search field
            NSApp.keyWindow?.makeFirstResponder(nil)
        case "Ingest":
            showingIngestProgress.toggle()
        case "Walkthrough":
            showingWalkthrough.toggle()
        case "Settings":
            showingSettings.toggle()
        case "Sync":
            onSync()
        case "Share":
            onShare()
        case "Export":
            onExport()
        default:
            break
        }
    }
    
    private func setupDefaultToolbar() {
        toolbarActions = [
            ToolbarAction.defaultActions[0], // New Project
            ToolbarAction.defaultActions[1], // Import
            ToolbarAction.defaultActions[2], // Filter
            ToolbarAction.defaultActions[3], // Search
            ToolbarAction.defaultActions[4], // Ingest
            ToolbarAction.defaultActions[5], // Walkthrough
            ToolbarAction.defaultActions[7], // Sync
            ToolbarAction.defaultActions[8], // Share
            ToolbarAction.defaultActions[6], // Settings
        ]
    }
}

// MARK: - Preview

