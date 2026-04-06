// SLATE — AIScoreBadge
// Shared composite AI score capsule for grid, list, and multicam surfaces.

import SwiftUI

struct AIScoreBadge: View {
    let score: Double

    private var rounded: Int { Int(score.rounded()) }

    var body: some View {
        Text("AI \(rounded)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.pink.opacity(0.16))
            .foregroundColor(.pink)
            .cornerRadius(4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("AI score \(rounded)")
    }
}
