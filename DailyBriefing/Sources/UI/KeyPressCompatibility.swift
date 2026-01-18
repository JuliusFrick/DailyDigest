import SwiftUI

/// Compatibility helpers for SwiftUI's `onKeyPress` API.
///
/// Newer SwiftUI versions expose `onKeyPress(keys:phases:action:)` and
/// `onKeyPress(characters:phases:action:)` but not a `modifiers:` parameter.
/// This wrapper restores a convenient `modifiers:` label for call-sites.
extension View {
    func onKeyPress(
        _ key: KeyEquivalent,
        modifiers: EventModifiers = [],
        phases: KeyPress.Phases = [.down],
        _ action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(keys: [key], phases: phases) { keyPress in
            guard keyPress.modifiers.isSuperset(of: modifiers) else { return .ignored }
            return action()
        }
    }
    
    func onKeyPress(
        _ characters: String,
        modifiers: EventModifiers = [],
        phases: KeyPress.Phases = [.down],
        _ action: @escaping () -> KeyPress.Result
    ) -> some View {
        onKeyPress(characters: CharacterSet(charactersIn: characters), phases: phases) { keyPress in
            guard keyPress.modifiers.isSuperset(of: modifiers) else { return .ignored }
            return action()
        }
    }
}
