# Daily Briefing PRD

Generated: 1/19/2026, 5:14:27 PM

## US-001: TTS Service - macOS Native Voice
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich das Briefing mit der nativen macOS TTS Engine vorlesen lassen können

### Acceptance Criteria
- [ ] Erstelle TTSService.swift in Core/Services/TTS/
- [ ] TTSProtocol definiert: speak(text:), pause(), resume(), stop(), setRate(), setVoice()
- [ ] AppleTTSService implementiert NSSpeechSynthesizer
- [ ] Verfügbare Stimmen werden aus NSSpeechSynthesizer.availableVoices geladen
- [ ] Geschwindigkeit ist einstellbar (0.5x - 2.0x)
- [ ] AppState.toggleAudioPlayback() ruft TTSService auf
- [ ] swift build kompiliert ohne Fehler

---

## US-004: Briefing Cache Service
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich vergangene Briefings lokal gecached haben für Offline-Zugriff

### Acceptance Criteria
- [ ] Erstelle BriefingCacheService.swift in Core/Services/
- [ ] Briefings werden als JSON in Application Support gespeichert
- [ ] Methoden: save(briefing:), loadLatest(), loadAll(), delete(id:), clearAll()
- [ ] Maximale Cache-Größe konfigurierbar (default: 50 Briefings)
- [ ] Älteste Briefings werden automatisch gelöscht wenn Limit erreicht
- [ ] BriefingGenerationService speichert neue Briefings automatisch
- [ ] swift build kompiliert ohne Fehler

---

## US-007: Notification Service Grundgerüst
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich Benachrichtigungen für das morgendliche Briefing erhalten

### Acceptance Criteria
- [ ] Erstelle NotificationService.swift in Core/Services/
- [ ] UNUserNotificationCenter Permission-Request beim ersten Start
- [ ] Methode scheduleMorningReminder(at: Date) plant tägliche Notification
- [ ] Notification-Content: 'Dein Daily Briefing ist bereit'
- [ ] Tap auf Notification öffnet die App und zeigt Dashboard
- [ ] SchedulingService ruft NotificationService nach Briefing-Generierung auf
- [ ] swift build kompiliert ohne Fehler

---

## US-009: Slack Source - Channel Fetching
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich sehen welche Slack-Channels verfügbar sind nach dem OAuth

### Acceptance Criteria
- [ ] SlackSource.swift: Methode fetchChannels() -> [SlackChannel]
- [ ] API Call zu conversations.list mit types=public_channel,private_channel
- [ ] SlackChannel Model: id, name, isPrivate, memberCount
- [ ] Channels werden nach OAuth automatisch geladen
- [ ] @Published var availableChannels: [SlackChannel] in SlackSource
- [ ] swift build kompiliert ohne Fehler

---

## US-012: App Intents für Shortcuts - Generate Briefing
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich via Shortcuts App ein Briefing generieren können

### Acceptance Criteria
- [ ] BriefingIntents.swift erweitern
- [ ] GenerateBriefingIntent: AppIntent Protocol implementieren
- [ ] title: 'Generate Daily Briefing'
- [ ] perform() ruft BriefingGenerationService.generateBriefing() auf
- [ ] Rückgabewert: IntentResult mit Briefing-Summary als String
- [ ] Intent ist in Shortcuts App sichtbar
- [ ] swift build kompiliert ohne Fehler

---

## US-014: Launch at Login
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich die App beim Mac-Start automatisch starten

### Acceptance Criteria
- [ ] Erstelle LaunchAtLoginService.swift in Core/Services/
- [ ] Verwendet SMAppService (macOS 13+) für Login Item
- [ ] Methoden: enable(), disable(), isEnabled() -> Bool
- [ ] In SettingsView: Toggle 'Bei Anmeldung starten'
- [ ] Toggle-State synchronisiert mit tatsächlichem Login Item Status
- [ ] swift build kompiliert ohne Fehler

---

## US-016: Markdown Rendering für Summary
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich dass die KI-Summary mit Markdown formatiert dargestellt wird

### Acceptance Criteria
- [ ] SummaryCard verwendet AttributedString für Markdown
- [ ] Unterstützte Formate: **bold**, *italic*, - Listen, ## Headings
- [ ] Links sind klickbar und öffnen im Browser
- [ ] Code-Blöcke haben monospaced Font
- [ ] Rendering funktioniert in Light und Dark Mode
- [ ] swift build kompiliert ohne Fehler

---

## US-018: Deep Links zu Source-Items
**Priority:** 🔴 High | **Status:** ✅ Passing

> Als User möchte ich direkt zur Original-Quelle springen können

### Acceptance Criteria
- [ ] BriefingItemRow: Tap öffnet deepLink URL im Standard-Browser
- [ ] Gmail Items: Link zu https://mail.google.com/mail/u/0/#inbox/{messageId}
- [ ] Calendar Items: Link zu Google Calendar Event
- [ ] Jira Items: Link zu Jira Issue URL
- [ ] Slack Items: Link zu slack://channel?team={teamId}&id={channelId}
- [ ] Visueller Indikator (Pfeil-Icon) wenn deepLink vorhanden
- [ ] swift build kompiliert ohne Fehler

---

## US-002: TTS Service - OpenAI Integration
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich OpenAI TTS als Alternative nutzen können für natürlichere Stimmen

### Acceptance Criteria
- [ ] Erstelle OpenAITTSService.swift in Core/Services/TTS/
- [ ] Implementiert TTSProtocol
- [ ] API Call zu https://api.openai.com/v1/audio/speech
- [ ] Unterstützt Stimmen: alloy, echo, fable, onyx, nova, shimmer
- [ ] Audio wird als MP3/AAC empfangen und mit AVAudioPlayer abgespielt
- [ ] API Key wird aus Keychain geladen (selber Key wie LLM)
- [ ] swift build kompiliert ohne Fehler

---

## US-005: Offline Mode Detection
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich einen Offline-Indikator sehen und auf gecachte Briefings zugreifen können

### Acceptance Criteria
- [ ] Erstelle NetworkMonitor.swift in Core/Services/ mit NWPathMonitor
- [ ] AppState hat @Published var isOnline: Bool
- [ ] DashboardView zeigt Offline-Banner wenn !isOnline
- [ ] Bei Offline: Button 'Letztes Briefing anzeigen' lädt aus Cache
- [ ] Bei Offline + Ollama konfiguriert: Briefing-Generierung möglich
- [ ] Statusbar Icon ändert Farbe bei Offline (grau statt bunt)
- [ ] swift build kompiliert ohne Fehler

---

## US-008: Notification Settings UI
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich Benachrichtigungen konfigurieren können

### Acceptance Criteria
- [ ] In SettingsView: Section 'Benachrichtigungen'
- [ ] Toggle: Benachrichtigungen aktivieren/deaktivieren
- [ ] Toggle: Morning Reminder aktivieren
- [ ] DatePicker für Reminder-Zeit
- [ ] Button: Notification-Berechtigung erneut anfragen (wenn verweigert)
- [ ] Status-Anzeige ob Berechtigung erteilt wurde
- [ ] swift build kompiliert ohne Fehler

---

## US-010: Slack Config View - Channel Selection
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich auswählen welche Slack-Channels im Briefing erscheinen

### Acceptance Criteria
- [ ] SlackConfigView.swift erweitern um Channel-Liste
- [ ] Jeder Channel hat Toggle (Include/Exclude)
- [ ] Suchfeld zum Filtern der Channels
- [ ] Ausgewählte Channels werden in UserDefaults gespeichert
- [ ] SlackSource.fetchItems() filtert nach ausgewählten Channels
- [ ] Preview zeigt Anzahl ausgewählter Channels
- [ ] swift build kompiliert ohne Fehler

---

## US-013: App Intents für Shortcuts - Additional Actions
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich weitere Shortcuts-Aktionen nutzen können

### Acceptance Criteria
- [ ] GetTodaysMeetingsIntent: Gibt Kalender-Termine als String zurück
- [ ] GetUnreadCountIntent: Gibt Anzahl ungelesener E-Mails/Slack zurück
- [ ] PlayBriefingIntent: Startet TTS Playback des letzten Briefings
- [ ] Alle Intents haben deutsche Titel und Beschreibungen
- [ ] Intents sind in Shortcuts App sichtbar und ausführbar
- [ ] swift build kompiliert ohne Fehler

---

## US-015: Privacy Settings
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich meine Daten verwalten und löschen können

### Acceptance Criteria
- [ ] In SettingsView: Section 'Datenschutz'
- [ ] Button: Cache leeren (löscht alle gecachten Briefings)
- [ ] Button: Alle Credentials löschen (Keychain leeren)
- [ ] Button: Alle Daten exportieren (JSON Export)
- [ ] Jeder Button hat Bestätigungsdialog
- [ ] Nach Credential-Löschung: Alle Sources auf disconnected setzen
- [ ] swift build kompiliert ohne Fehler

---

## US-017: Error Recovery UI
**Priority:** Ez🟡 Medium | **Status:** ✅ Passing

> Als User möchte ich bei Fehlern klare Anweisungen zur Behebung sehen

### Acceptance Criteria
- [ ] Bei llmNotConfigured: Alert mit Button 'KI konfigurieren' → öffnet LLMSettingsView
- [ ] Bei noSourcesConnected: Alert mit Button 'Quellen verbinden' → öffnet SourcesView
- [ ] Bei tokenExpired: Alert mit Button 'Erneut verbinden' → startet OAuth
- [ ] Bei networkError: Offline-Banner mit 'Cached Briefing laden' Button
- [ ] Alle Error-Alerts haben 'Hilfe' Button der FAQ/Support öffnet
- [ ] swift build kompiliert ohne Fehler

---

## US-003: TTS Settings UI
**Priority:** 🟢 Low | **Status:** ✅ Passing

> Als User möchte ich in den Settings die TTS Engine und Stimme auswählen können

### Acceptance Criteria
- [ ] Erstelle TTSSettingsView.swift in Features/Settings/
- [ ] Picker für TTS Engine: Apple Native, OpenAI TTS
- [ ] Stimmen-Picker zeigt verfügbare Stimmen der ausgewählten Engine
- [ ] Geschwindigkeits-Slider (0.5x - 2.0x)
- [ ] Preview-Button zum Testen der Stimme
- [ ] Settings werden in UserSettings SwiftData Model gespeichert
- [ ] SettingsView.swift enthält NavigationLink zu TTSSettingsView
- [ ] swift build kompiliert ohne Fehler

---

## US-006: Briefing History View
**Priority:** 🟢 Low | **Status:** ✅ Passing

> Als User möchte ich vergangene Briefings ansehen können

### Acceptance Criteria
- [ ] Erstelle BriefingHistoryView.swift in Features/Dashboard/
- [ ] Liste aller gecachten Briefings mit Datum
- [ ] Tap auf Eintrag zeigt das alte Briefing an
- [ ] Swipe-to-Delete für einzelne Einträge
- [ ] Button 'Alle löschen' mit Bestätigungsdialog
- [ ] AppState.Tab erweitern um .history case
- [ ] SidebarView zeigt neuen History Tab
- [ ] swift build kompiliert ohne Fehler

---

## US-011: Slack Config View - Content Toggles
**Priority:** 🟢 Low | **Status:** ✅ Passing

> Als User möchte ich konfigurieren welche Slack-Inhalte erfasst werden

### Acceptance Criteria
- [ ] SlackConfigView.swift: Section 'Inhaltstypen'
- [ ] Toggle: Ungelesene DMs einbeziehen
- [ ] Toggle: Mentions (@user) einbeziehen
- [ ] Toggle: Reactions auf eigene Nachrichten
- [ ] Toggle: Slack Reminders einbeziehen
- [ ] Alle Toggles werden in UserDefaults gespeichert
- [ ] SlackSource.fetchItems() respektiert alle Toggles
- [ ] swift build kompiliert ohne Fehler

---

