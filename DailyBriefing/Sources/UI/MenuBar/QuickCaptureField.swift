import SwiftUI

struct QuickCaptureField: View {
    @EnvironmentObject private var appState: AppState
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var justSubmitted: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(.secondary)
            
            TextField("Type a note to self...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .rounded))
                .focused($isFocused)
                .onSubmit {
                    submitNote()
                }
            
            if !text.isEmpty {
                Button(action: submitNote) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isFocused ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal)
        .overlay {
            if justSubmitted {
                Text("Saved!")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(4)
                    .background(Color.white)
                    .cornerRadius(4)
                    .shadow(radius: 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { justSubmitted = false }
                        }
                    }
            }
        }
    }
    
    private func submitNote() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let noteContent = text
        appState.addQuickNote(noteContent)
        
        // Clear and Feedback
        text = ""
        withAnimation {
            justSubmitted = true
        }
    }
}
