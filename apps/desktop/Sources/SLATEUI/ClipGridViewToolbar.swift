// SLATE — ClipGridViewToolbar
// Owned by: Claude Code
//
// Toolbar for clip grid view with search, sort, and filter controls.

import SwiftUI
import SLATECore
import SLATESharedTypes

struct ClipGridViewToolbar: View {
    @Binding var viewMode: ViewMode
    @Binding var sortBy: SortOption
    @Binding var sortOrder: SortOrder
    @Binding var searchText: String
    @Binding var filterStatus: ReviewStatus?
    @Binding var showingFilterMenu: Bool
    let clipCount: Int
    let searchPrompt: String
    let hasActiveFilters: Bool
    let clearFilters: () -> Void
    
    var body: some View {
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

            if hasActiveFilters {
                Button("Clear", action: clearFilters)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            
            // Clip count
            Text("\(clipCount) clips")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Filter Menu

struct FilterMenu: View {
    @Binding var selectedStatus: ReviewStatus?
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Filter by Status")
                .font(.headline)
                .padding()
            
            Divider()
            
            ForEach(ReviewStatus.allCases, id: \.self) { status in
                Button {
                    selectedStatus = status == selectedStatus ? nil : status
                } label: {
                    HStack {
                        Image(systemName: selectedStatus == status ? "checkmark.circle.fill" : "circle")
                        Text(status.displayName)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            
            Divider()
            
            Button("Clear Filter", action: onClear)
                .padding()
        }
    }
}
