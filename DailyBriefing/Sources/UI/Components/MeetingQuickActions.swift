import SwiftUI

/// Quick action toolbar that appears on hover over meetings
struct MeetingQuickActions: View {
    let meeting: BriefingItem
    var onJoin: (() -> Void)?
    var onRecord: (() -> Void)?
    var onNotes: (() -> Void)?
    var onDetails: (() -> Void)?
    
    @State private var hoveredAction: String?
    
    private var hasMeetingLink: Bool {
        meeting.metadata["meetingLink"] != nil
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if hasMeetingLink {
                quickActionButton(
                    icon: "video.fill",
                    label: "Beitreten",
                    id: "join",
                    color: .green
                ) {
                    onJoin?()
                }
            }
            
            quickActionButton(
                icon: "mic.fill",
                label: "Aufnehmen",
                id: "record",
                color: .red
            ) {
                onRecord?()
            }
            
            quickActionButton(
                icon: "note.text",
                label: "Notizen",
                id: "notes",
                color: .blue
            ) {
                onNotes?()
            }
            
            quickActionButton(
                icon: "info.circle.fill",
                label: "Details",
                id: "details",
                color: .secondary
            ) {
                onDetails?()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        )
    }
    
    private func quickActionButton(
        icon: String,
        label: String,
        id: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(hoveredAction == id ? color : .primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(hoveredAction == id ? color.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovered in
            hoveredAction = isHovered ? id : nil
        }
    }
}

/// Modifier to add quick actions on hover
struct QuickActionsOverlayModifier: ViewModifier {
    let meeting: BriefingItem
    var onJoin: (() -> Void)?
    var onRecord: (() -> Void)?
    var onNotes: (() -> Void)?
    var onDetails: (() -> Void)?
    
    @State private var isHovered = false
    @State private var showActions = false
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if showActions {
                    MeetingQuickActions(
                        meeting: meeting,
                        onJoin: onJoin,
                        onRecord: onRecord,
                        onNotes: onNotes,
                        onDetails: onDetails
                    )
                    .offset(x: -8, y: 8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .onHover { hovering in
                isHovered = hovering
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    // Delay showing, immediate hide
                    if hovering {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if isHovered {
                                showActions = true
                            }
                        }
                    } else {
                        showActions = false
                    }
                }
            }
    }
}

extension View {
    func meetingQuickActions(
        for meeting: BriefingItem,
        onJoin: (() -> Void)? = nil,
        onRecord: (() -> Void)? = nil,
        onNotes: (() -> Void)? = nil,
        onDetails: (() -> Void)? = nil
    ) -> some View {
        modifier(QuickActionsOverlayModifier(
            meeting: meeting,
            onJoin: onJoin,
            onRecord: onRecord,
            onNotes: onNotes,
            onDetails: onDetails
        ))
    }
}

struct MeetingQuickActions_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Hover over me")
                .padding()
                .background(Color.tuiPanel)
                .meetingQuickActions(
                    for: BriefingItem(
                        title: "Team Standup",
                        metadata: ["meetingLink": "https://meet.google.com/abc"]
                    ),
                    onJoin: { print("Join") },
                    onRecord: { print("Record") }
                )
        }
        .padding(50)
        .background(Color.tuiBackground)
    }
}
