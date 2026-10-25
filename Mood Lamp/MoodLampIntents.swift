import AppIntents
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - MoodLampScene

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

    /// Characteristic colours for swatch previews.
    var colors: [Color] {
        switch self {
        case .warmWhite:   return [Color(red: 1.0, green: 0.85, blue: 0.6), Color(red: 1.0, green: 0.75, blue: 0.45)]
        case .daylight:    return [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.8, green: 0.9, blue: 1.0)]
        case .coolWhite:   return [Color(red: 0.85, green: 0.92, blue: 1.0), Color(red: 0.75, green: 0.85, blue: 0.98)]
        case .nightLight:  return [Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 0.9, green: 0.4, blue: 0.1)]
        case .focus:       return [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.7, green: 0.85, blue: 1.0)]
        case .relax:       return [Color(red: 1.0, green: 0.8, blue: 0.5), Color(red: 0.95, green: 0.65, blue: 0.3)]
        case .tvTime:      return [Color(red: 0.3, green: 0.3, blue: 0.6), Color(red: 0.15, green: 0.15, blue: 0.4)]
        case .cozy:        return [Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.15)]
        case .candlelight: return [Color(red: 1.0, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.5, blue: 0.05)]
        case .fireplace:   return [Color(red: 1.0, green: 0.4, blue: 0.0), Color(red: 1.0, green: 0.2, blue: 0.0), Color(red: 0.8, green: 0.1, blue: 0.0)]
        case .sunset:      return [Color(red: 1.0, green: 0.5, blue: 0.2), Color(red: 1.0, green: 0.3, blue: 0.4), Color(red: 0.7, green: 0.2, blue: 0.5)]
        case .ocean:       return [Color(red: 0.0, green: 0.5, blue: 0.8), Color(red: 0.0, green: 0.3, blue: 0.6), Color(red: 0.0, green: 0.7, blue: 0.9)]
        case .party:       return [Color.red, Color.blue, Color.green, Color.purple]
        case .romance:     return [Color(red: 0.9, green: 0.2, blue: 0.4), Color(red: 0.7, green: 0.1, blue: 0.3)]
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

// MARK: - Intents

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

struct SetColorIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood Lamp colour"
    @Parameter(title: "Hue (0-360)") var hue: Int
    @Parameter(title: "Saturation (0-100)") var saturation: Int

    func perform() async throws -> some IntentResult {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        PlatformColor(
            hue: CGFloat(hue) / 360,
            saturation: CGFloat(saturation) / 100,
            brightness: 1,
            alpha: 1
        ).getRed(&r, green: &g, blue: &b, alpha: &a)
        try await WizClient.shared.setPilot([
            "state": true,
            "r": Int((r * 255).rounded()),
            "g": Int((g * 255).rounded()),
            "b": Int((b * 255).rounded()),
        ])
        return .result()
    }
}

// MARK: - Shortcuts

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
        AppShortcut(
            intent: SetColorIntent(),
            phrases: ["Set \(.applicationName) colour"],
            shortTitle: "Set colour", systemImageName: "paintpalette.fill")
    }
}
