import SwiftUI

// MARK: - InsightStream

struct InsightStream: View {
    @EnvironmentObject private var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("LATEST INSIGHT", systemImage: "sparkles")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            if let briefing = appState.currentBriefing {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Extracting points simply by splitting newlines for now, strictly conceptual
                    // In a real app we might parse the markdown list
                    let points = extractPoints(from: briefing.summary)
                    
                    ForEach(points.prefix(3), id: \.self) { point in
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                                .padding(4)
                            
                            Text(point)
                                .font(.system(.caption, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Color.tuiHover)
                .cornerRadius(6)
            } else {
                Text("No recent insights available.")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.tuiHover)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, Spacing.md)
    }
    
    // Naive helper to extract "points" from a summary paragraph
    private func extractPoints(from text: String) -> [String] {
        // Assume sentences are points if not formatted as list
        let sentences = text.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.last == "." ? $0 : $0 + "." }
            
        return sentences
    }
}
