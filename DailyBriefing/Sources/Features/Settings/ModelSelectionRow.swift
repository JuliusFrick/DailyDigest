import SwiftUI

/// A row for selecting a model for a specific feature
struct ModelSelectionRow: View {
    let feature: FeatureType
    let title: String
    let icon: String
    
    @StateObject private var modelService = ModelSelectionService.shared
    @State private var showingPicker = false
    
    private var currentModel: ModelProvider {
        modelService.getModel(for: feature)
    }
    
    private var availableModels: [ModelProvider] {
        modelService.availableModels(for: feature)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: icon)
                
                Spacer()
                
                Button {
                    showingPicker.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: currentModel.iconName)
                            .foregroundStyle(currentModel.isOnDevice ? .green : .blue)
                            .font(.caption)
                        
                        Text(currentModel.shortName)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Show fallback status if active
            if let fallback = modelService.lastFallback, fallback.feature == feature {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption2)
                    
                    Text("Using fallback: \(fallback.to.displayName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 20) // Align with label text
            }
        }
        .sheet(isPresented: $showingPicker) {
            ModelPickerView(
                feature: feature,
                selectedModel: currentModel,
                availableModels: availableModels,
                onSelect: { model in
                    modelService.setModel(for: feature, provider: model)
                    showingPicker = false
                }
            )
        }
    }
}

// MARK: - Model Picker View

struct ModelPickerView: View {
    let feature: FeatureType
    let selectedModel: ModelProvider
    let availableModels: [ModelProvider]
    let onSelect: (ModelProvider) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    private var groupedModels: [(String, [ModelProvider])] {
        let grouped = Dictionary(grouping: availableModels) { $0.providerName }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(groupedModels, id: \.0) { providerName, models in
                    Section {
                        ForEach(models, id: \.self) { model in
                            ModelPickerRow(
                                model: model,
                                isSelected: model == selectedModel,
                                onSelect: {
                                    onSelect(model)
                                }
                            )
                        }
                    } header: {
                        Text(providerName)
                    }
                }
            }
            .navigationTitle("Modell wählen")
            .navigationSubtitle(feature.displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 600)
    }
}

// MARK: - Model Picker Row

struct ModelPickerRow: View {
    let model: ModelProvider
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var modelInfo: ModelInfo {
        ModelInfo.info(for: model)
    }
    
    var body: some View {
        Button {
            onSelect()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(model.color.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: model.iconName)
                        .foregroundStyle(model.color)
                        .font(.system(size: 16))
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.shortName)
                            .font(.headline)
                        
                        if model.isOnDevice {
                            Text("🏠")
                                .font(.caption)
                        } else {
                            Text("☁️")
                                .font(.caption)
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    
                    Text(modelInfo.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    
                    // Additional info
                    HStack(spacing: 12) {
                        if let contextWindow = modelInfo.contextWindow {
                            HStack(spacing: 2) {
                                Image(systemName: "text.alignleft")
                                    .font(.caption2)
                                Text("\(formatContextWindow(contextWindow))")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        if let cost = modelInfo.costPer1MTokens {
                            HStack(spacing: 2) {
                                Image(systemName: "dollarsign.circle")
                                    .font(.caption2)
                                Text("$\(String(format: "%.2f", cost))/M")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        } else if model.isOnDevice {
                            HStack(spacing: 2) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption2)
                                Text("Kostenlos")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.green)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M tokens"
        } else if tokens >= 1000 {
            return "\(tokens / 1000)K tokens"
        } else {
            return "\(tokens) tokens"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        ModelSelectionRow(
            feature: .transcription,
            title: "Transkription",
            icon: "waveform"
        )
        
        ModelSelectionRow(
            feature: .chat,
            title: "Chat",
            icon: "message"
        )
        
        ModelSelectionRow(
            feature: .actionItems,
            title: "Action Items",
            icon: "checkmark.circle"
        )
    }
    .padding()
}
