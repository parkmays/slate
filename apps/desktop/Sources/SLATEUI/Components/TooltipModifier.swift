// SLATE — TooltipModifier
// Owned by: Claude Code
//
// Reusable tooltip modifier that supports keyboard shortcuts display
// and consistent styling across the app.

import SwiftUI

struct TooltipModifier: ViewModifier {
    let text: String
    let shortcut: KeyEquivalent?
    let modifiers: EventModifiers
    
    init(text: String, shortcut: KeyEquivalent? = nil, modifiers: EventModifiers = []) {
        self.text = text
        self.shortcut = shortcut
        self.modifiers = modifiers
    }
    
    func body(content: Content) -> some View {
        content
            .help(tooltipText)
    }
    
    private var tooltipText: String {
        guard let shortcut = shortcut else { return text }
        
        let modifierSymbols: [String] = {
            var symbols: [String] = []
            if modifiers.contains(.command) { symbols.append("⌘") }
            if modifiers.contains(.option) { symbols.append("⌥") }
            if modifiers.contains(.shift) { symbols.append("⇧") }
            if modifiers.contains(.control) { symbols.append("⌃") }
            return symbols
        }()
        
        let shortcutString = modifierSymbols.joined() + shortcut.character.uppercased()
        return "\(text) (\(shortcutString))"
    }
}

extension View {
    /// Adds a tooltip with optional keyboard shortcut
    /// - Parameters:
    ///   - text: The tooltip text
    ///   - shortcut: Optional keyboard shortcut
    ///   - modifiers: Optional modifier keys for the shortcut
    func tooltip(_ text: String, shortcut: KeyEquivalent? = nil, modifiers: EventModifiers = []) -> some View {
        modifier(TooltipModifier(text: text, shortcut: shortcut, modifiers: modifiers))
    }
}

// MARK: - Preview

struct TooltipModifier_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Button("Filter") {}
                .tooltip("Filter clips by status", shortcut: "f", modifiers: .command)
            
            Button("New Project") {}
                .tooltip("Create a new project", shortcut: "n", modifiers: .command)
            
            Button("Walkthrough") {}
                .tooltip("Show the interactive walkthrough", shortcut: "w", modifiers: [.command, .shift])
        }
        .padding()
    }
}
