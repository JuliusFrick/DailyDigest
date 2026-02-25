# App Shell Structure

Die App ist jetzt als klarer Shell-Aufbau organisiert.

## Einstieg
- `Sources/App/ContentView.swift`
  - Entscheidet nur noch zwischen Onboarding und App-Shell.

## Shell-Module
- `Sources/App/Shell/AppShellView.swift`
  - Hauptlayout mit Header, Sidebar, Content und Statusbar.
- `Sources/App/Shell/AppShellHeaderView.swift`
  - Globale Aktionen (Quick, Detail, Play/Pause) und Kontext.
- `Sources/App/Shell/AppShellSidebarView.swift`
  - Strukturierte Navigation in Gruppen.
- `Sources/App/Shell/AppShellContentView.swift`
  - Zentrales Routing zu allen Hauptbereichen.
- `Sources/App/Shell/AppShellStatusBarView.swift`
  - Live-Zustand (Online, Quellen, Progress, Hotkeys).
- `Sources/App/Shell/AppShellKeyboardShortcuts.swift`
  - Tastaturkürzel an einer Stelle gebündelt.

## Vorteile
- Verantwortlichkeiten sind getrennt und wartbar.
- Navigation ist zentral statt verteilt.
- Neue Panels/Aktionen lassen sich ohne Umbau der ganzen View-Hierarchie ergänzen.
