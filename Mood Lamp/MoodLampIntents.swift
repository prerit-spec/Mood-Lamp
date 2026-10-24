import AppIntents

/// Scenes shared by the screen and by Siri. Raw values are WiZ scene IDs.
enum MoodLampScene: String, AppEnum, CaseIterable {
    case warmWhite, daylight, coolWhite, nightLight, focus, relax, tvTime
    case cozy, candlelight, fireplace, sunset, ocean, party, romance

    var sceneId: Int {
        switch self {
        case .ocean: return 1
        case .romance: return 2
        case .sunset: return 3
        case .party: return 4
        case .fireplace: return 5
        case .cozy: return 6
        case .warmWhite: return 11
        case .daylight: return 12
        case .coolWhite: return 13
        case .nightLight: return 14
        case .focus: return 15
        case .relax: return 16
        case .tvTime: return 18
        case .candlelight: return 29
        }
    }

    var label: String {
        switch self {
        case .warmWhite: return "Warm white"
        case .daylight: return "Daylight"
        case .coolWhite: return "Cool white"
        case .nightLight: return "Night light"
        case .focus: return "Focus"
        case .relax: return "Relax"
        case .tvTime: return "TV time"
        case .cozy: return "Cozy"
        case .candlelight: return "Candlelight"
        case .fireplace: return "Fireplace"
        case .sunset: return "Sunset"
        case .ocean: return "Ocean"
        case .party: return "Party"
        case .romance: return "Romance"
        }
    }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let caseDisplayRepresentations: [MoodLampScene: DisplayRepresentation] = [
        .warmWhite: "Warm white", .daylight: "Daylight", .coolWhite: "Cool white",
        .nightLight: "Night light", .focus: "Focus", .relax: "Relax", .tvTime: "TV time",
        .cozy: "Cozy", .candlelight: "Candlelight", .fireplace: "Fireplace",
        .sunset: "Sunset", .ocean: "Ocean", .party: "Party", .romance: "Romance",
    ]
}

struct TurnMoodLampOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Mood Lamp on"
    func perform() async throws -> some IntentResult {
        try await WizClient.shared.setPilot(["state": true])
        return .result()
    }
}

struct TurnMoodLampOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Mood Lamp off"
    func perform() async throws -> some IntentResult {
        try await WizClient.shared.setPilot(["state": false])
        return .result()
    }
}

struct SetSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood Lamp scene"
    @Parameter(title: "Scene") var scene: MoodLampScene
    func perform() async throws -> some IntentResult {
        try await WizClient.shared.setPilot(["state": true, "sceneId": scene.sceneId])
        return .result()
    }
}

/// Appears in Shortcuts. Siri will ask "what brightness?" if you run it by voice.
struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood Lamp brightness"
    @Parameter(title: "Brightness (10 to 100)") var level: Int
    func perform() async throws -> some IntentResult {
        let value = min(100, max(10, level))
        try await WizClient.shared.setPilot(["state": true, "dimming": value])
        return .result()
    }
}

struct MoodLampShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TurnMoodLampOnIntent(),
            phrases: ["Turn on \(.applicationName)", "Turn on the \(.applicationName)", "\(.applicationName) on"],
            shortTitle: "Turn on", systemImageName: "lightbulb.fill")
        AppShortcut(
            intent: TurnMoodLampOffIntent(),
            phrases: ["Turn off \(.applicationName)", "Turn off the \(.applicationName)", "\(.applicationName) off"],
            shortTitle: "Turn off", systemImageName: "lightbulb.slash")
        AppShortcut(
            intent: SetSceneIntent(),
            phrases: ["\(.applicationName) \(\.$scene)", "Set \(.applicationName) to \(\.$scene)"],
            shortTitle: "Set scene", systemImageName: "sparkles")
    }
}
