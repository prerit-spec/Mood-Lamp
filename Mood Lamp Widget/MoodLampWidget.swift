import AppIntents
import SwiftUI
import WidgetKit

nonisolated private let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"

// MARK: - Scene Information & Visual Styling

struct WidgetSceneInfo: Codable, Identifiable {
    let id: Int
    let title: String
}

private struct WidgetSavedLamp: Codable {
    let id: UUID
    var name: String
    var ip: String
    var mac: String
}

struct WidgetSceneVisual {
    let id: Int
    let title: String
    let icon: String
    let gradient: [Color]
}

func visualForScene(id: Int, fallbackTitle: String = "") -> WidgetSceneVisual {
    switch id {
    case 1:
        return WidgetSceneVisual(
            id: 1,
            title: "Ocean",
            icon: "water.waves",
            gradient: [Color(red: 0.0, green: 0.58, blue: 0.88), Color(red: 0.0, green: 0.35, blue: 0.72)]
        )
    case 2:
        return WidgetSceneVisual(
            id: 2,
            title: "Romance",
            icon: "heart.fill",
            gradient: [Color(red: 0.95, green: 0.25, blue: 0.45), Color(red: 0.7, green: 0.1, blue: 0.35)]
        )
    case 3:
        return WidgetSceneVisual(
            id: 3,
            title: "Sunset",
            icon: "sunset.fill",
            gradient: [Color(red: 1.0, green: 0.48, blue: 0.22), Color(red: 0.85, green: 0.2, blue: 0.5)]
        )
    case 4:
        return WidgetSceneVisual(
            id: 4,
            title: "Party",
            icon: "sparkles",
            gradient: [Color(red: 0.95, green: 0.2, blue: 0.6), Color(red: 0.45, green: 0.3, blue: 0.95)]
        )
    case 5:
        return WidgetSceneVisual(
            id: 5,
            title: "Fireplace",
            icon: "flame.fill",
            gradient: [Color(red: 1.0, green: 0.38, blue: 0.05), Color(red: 0.85, green: 0.15, blue: 0.0)]
        )
    case 6:
        return WidgetSceneVisual(
            id: 6,
            title: "Cozy",
            icon: "cup.and.saucer.fill",
            gradient: [Color(red: 1.0, green: 0.68, blue: 0.25), Color(red: 0.92, green: 0.45, blue: 0.12)]
        )
    case 11:
        return WidgetSceneVisual(
            id: 11,
            title: "Warm white",
            icon: "sun.max.fill",
            gradient: [Color(red: 1.0, green: 0.85, blue: 0.55), Color(red: 1.0, green: 0.7, blue: 0.35)]
        )
    case 12:
        return WidgetSceneVisual(
            id: 12,
            title: "Daylight",
            icon: "sun.horizon.fill",
            gradient: [Color(red: 0.9, green: 0.95, blue: 1.0), Color(red: 0.75, green: 0.88, blue: 1.0)]
        )
    case 13:
        return WidgetSceneVisual(
            id: 13,
            title: "Cool white",
            icon: "snowflake",
            gradient: [Color(red: 0.85, green: 0.92, blue: 1.0), Color(red: 0.7, green: 0.82, blue: 0.98)]
        )
    case 14:
        return WidgetSceneVisual(
            id: 14,
            title: "Night light",
            icon: "moon.stars.fill",
            gradient: [Color(red: 1.0, green: 0.55, blue: 0.18), Color(red: 0.85, green: 0.35, blue: 0.08)]
        )
    case 15:
        return WidgetSceneVisual(
            id: 15,
            title: "Focus",
            icon: "bolt.fill",
            gradient: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.75, green: 0.88, blue: 1.0)]
        )
    case 16:
        return WidgetSceneVisual(
            id: 16,
            title: "Relax",
            icon: "leaf.fill",
            gradient: [Color(red: 1.0, green: 0.8, blue: 0.48), Color(red: 0.92, green: 0.62, blue: 0.28)]
        )
    case 18:
        return WidgetSceneVisual(
            id: 18,
            title: "TV time",
            icon: "tv.fill",
            gradient: [Color(red: 0.4, green: 0.4, blue: 0.75), Color(red: 0.2, green: 0.2, blue: 0.45)]
        )
    case 29:
        return WidgetSceneVisual(
            id: 29,
            title: "Candlelight",
            icon: "flame",
            gradient: [Color(red: 1.0, green: 0.72, blue: 0.2), Color(red: 0.98, green: 0.48, blue: 0.05)]
        )
    default:
        let displayTitle = fallbackTitle.isEmpty ? "Scene \(id)" : fallbackTitle
        return WidgetSceneVisual(
            id: id,
            title: displayTitle,
            icon: "sparkles",
            gradient: [Color(red: 1.0, green: 0.65, blue: 0.25), Color(red: 0.9, green: 0.45, blue: 0.15)]
        )
    }
}

private func loadFavouriteScenes() -> [WidgetSceneInfo] {
    guard let defaults = UserDefaults(suiteName: appGroupIdentifier),
          let data = defaults.data(forKey: "favouriteWidgetScenes"),
          let decoded = try? JSONDecoder().decode([WidgetSceneInfo].self, from: data),
          !decoded.isEmpty else {
        return [
            WidgetSceneInfo(id: 6, title: "Cozy"),
            WidgetSceneInfo(id: 14, title: "Night light"),
            WidgetSceneInfo(id: 16, title: "Relax"),
            WidgetSceneInfo(id: 3, title: "Sunset"),
        ]
    }
    return Array(decoded.prefix(6))
}

// MARK: - Timeline Entry & Provider

struct MoodLampWidgetEntry: TimelineEntry {
    let date: Date
    let isConfigured: Bool
    let isOn: Bool
    let dimming: Int
    let lampName: String
    let activeSceneId: Int?
    let scenes: [WidgetSceneInfo]
}

struct MoodLampWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodLampWidgetEntry {
        MoodLampWidgetEntry(
            date: .now,
            isConfigured: true,
            isOn: true,
            dimming: 80,
            lampName: "Mood Lamp",
            activeSceneId: 6,
            scenes: loadFavouriteScenes()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodLampWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodLampWidgetEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func makeEntry() -> MoodLampWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let isConfigured = !(defaults?.string(forKey: "bulbIp") ?? "").isEmpty
        let isOn = defaults?.bool(forKey: "bulbOn") ?? false
        let rawDimming = defaults?.integer(forKey: "bulbDimming") ?? 80
        let dimming = rawDimming == 0 ? 80 : rawDimming
        let activeSceneId = defaults?.object(forKey: "bulbSceneId") as? Int

        var lampName = "Mood Lamp"
        if let data = defaults?.data(forKey: "savedLamps"),
           let lamps = try? JSONDecoder().decode([WidgetSavedLamp].self, from: data),
           let activeIdStr = defaults?.string(forKey: "activeLampId"),
           let activeId = UUID(uuidString: activeIdStr),
           let match = lamps.first(where: { $0.id == activeId }),
           !match.name.isEmpty {
            lampName = match.name
        }

        return MoodLampWidgetEntry(
            date: .now,
            isConfigured: isConfigured,
            isOn: isOn,
            dimming: dimming,
            lampName: lampName,
            activeSceneId: activeSceneId,
            scenes: loadFavouriteScenes()
        )
    }
}

// MARK: - App Intents for Interactive Controls

struct ToggleMoodLampWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Mood Lamp"

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let current = defaults?.bool(forKey: "bulbOn") ?? false
        let nextState = !current

        // Optimistically update shared defaults for instant widget response
        defaults?.set(nextState, forKey: "bulbOn")
        WidgetCenter.shared.reloadAllTimelines()

        do {
            try await WizClient.shared.setPilot(["state": nextState])
        } catch {
            // Revert if UDP communication failed
            defaults?.set(current, forKey: "bulbOn")
            WidgetCenter.shared.reloadAllTimelines()
            throw error
        }
        return .result()
    }
}

struct SetMoodLampWidgetSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood Lamp Scene"

    @Parameter(title: "Scene ID") var sceneId: Int

    init() {
        self.sceneId = 6
    }

    init(sceneId: Int) {
        self.sceneId = sceneId
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(true, forKey: "bulbOn")
        defaults?.set(sceneId, forKey: "bulbSceneId")
        WidgetCenter.shared.reloadAllTimelines()

        try await WizClient.shared.setPilot(["state": true, "sceneId": sceneId])
        return .result()
    }
}

struct SetMoodLampWidgetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Brightness Level"

    @Parameter(title: "Level") var level: Int

    init() {
        self.level = 80
    }

    init(level: Int) {
        self.level = level
    }

    func perform() async throws -> some IntentResult {
        let clamped = min(100, max(10, level))
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(true, forKey: "bulbOn")
        defaults?.set(clamped, forKey: "bulbDimming")
        WidgetCenter.shared.reloadAllTimelines()

        try await WizClient.shared.setPilot(["state": true, "dimming": clamped])
        return .result()
    }
}

struct StepMoodLampWidgetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Adjust Brightness Step"

    @Parameter(title: "Step Delta") var delta: Int

    init() {
        self.delta = 20
    }

    init(delta: Int) {
        self.delta = delta
    }

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        let current = defaults?.integer(forKey: "bulbDimming") ?? 80
        let effective = current == 0 ? 80 : current
        let target = min(100, max(10, effective + delta))

        defaults?.set(true, forKey: "bulbOn")
        defaults?.set(target, forKey: "bulbDimming")
        WidgetCenter.shared.reloadAllTimelines()

        try await WizClient.shared.setPilot(["state": true, "dimming": target])
        return .result()
    }
}

// MARK: - Widget View

struct MoodLampWidgetView: View {
    let entry: MoodLampWidgetEntry
    @Environment(\.widgetFamily) private var family

    private var auraColor: Color {
        if let sceneId = entry.activeSceneId {
            return visualForScene(id: sceneId).gradient.first ?? Color(red: 1.0, green: 0.65, blue: 0.22)
        }
        return Color(red: 1.0, green: 0.65, blue: 0.22)
    }

    var body: some View {
        Group {
            if entry.isConfigured {
                switch family {
                case .systemSmall:
                    smallWidget
                case .systemMedium:
                    mediumWidget
                case .systemLarge:
                    largeWidget
                case .accessoryCircular:
                    accessoryCircularView
                case .accessoryRectangular:
                    accessoryRectangularView
                case .accessoryInline:
                    accessoryInlineView
                default:
                    mediumWidget
                }
            } else {
                setupWidget
            }
        }
        .containerBackground(for: .widget) {
            widgetBackground
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var widgetBackground: some View {
        ZStack {
            Color(red: 0.08, green: 0.07, blue: 0.07)
            if entry.isOn {
                RadialGradient(
                    colors: [
                        auraColor.opacity(0.38),
                        auraColor.opacity(0.12),
                        Color.clear
                    ],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 220
                )
            }
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        VStack(spacing: 10) {
            // Top Bar
            HStack(spacing: 6) {
                Image(systemName: "lamp.table.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(entry.isOn ? auraColor : .secondary)
                Text(entry.lampName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.isOn ? "\(entry.dimming)%" : "OFF")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isOn ? auraColor : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
            }

            Spacer(minLength: 0)

            // Interactive Ambient Glowing Orb
            Button(intent: ToggleMoodLampWidgetIntent()) {
                ZStack {
                    if entry.isOn {
                        Circle()
                            .fill(auraColor.opacity(0.3))
                            .frame(width: 66, height: 66)
                            .blur(radius: 8)
                    }

                    Circle()
                        .fill(
                            entry.isOn
                                ? LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.82, blue: 0.45), Color(red: 0.98, green: 0.52, blue: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .frame(width: 58, height: 58)
                        .overlay(
                            Circle()
                                .strokeBorder(entry.isOn ? Color.white.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                        )

                    VStack(spacing: 2) {
                        Image(systemName: entry.isOn ? "power" : "lightbulb.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(entry.isOn ? Color(red: 0.16, green: 0.1, blue: 0.05) : Color.white.opacity(0.6))
                        Text(entry.isOn ? "ON" : "OFF")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(entry.isOn ? Color(red: 0.22, green: 0.12, blue: 0.05) : Color.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Bottom Quick Controls
            if entry.isOn {
                HStack(spacing: 8) {
                    Button(intent: StepMoodLampWidgetBrightnessIntent(delta: -20)) {
                        Image(systemName: "sun.min.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)

                    Button(intent: StepMoodLampWidgetBrightnessIntent(delta: 20)) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(intent: ToggleMoodLampWidgetIntent()) {
                    HStack(spacing: 5) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .bold))
                        Text("Turn On")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        HStack(spacing: 14) {
            // Left Deck: Hero Orb & Status
            VStack(spacing: 8) {
                Button(intent: ToggleMoodLampWidgetIntent()) {
                    ZStack {
                        if entry.isOn {
                            Circle()
                                .fill(auraColor.opacity(0.35))
                                .frame(width: 58, height: 58)
                                .blur(radius: 7)
                        }

                        Circle()
                            .fill(
                                entry.isOn
                                    ? LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.82, blue: 0.45), Color(red: 0.98, green: 0.52, blue: 0.15)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .strokeBorder(entry.isOn ? Color.white.opacity(0.35) : Color.white.opacity(0.12), lineWidth: 1)
                            )

                        Image(systemName: entry.isOn ? "power" : "lightbulb.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(entry.isOn ? Color(red: 0.2, green: 0.12, blue: 0.05) : Color.white.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text(entry.lampName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(entry.isOn ? auraColor : Color.secondary.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(entry.isOn ? "\(entry.dimming)% Bright" : "Turned Off")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 96)

            // Divider line
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 4)

            // Right Controls: Brightness Presets & Favorite Scenes
            VStack(alignment: .leading, spacing: 8) {
                // Brightness Presets
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("BRIGHTNESS")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.8))
                        Spacer()
                    }

                    HStack(spacing: 5) {
                        ForEach([25, 50, 75, 100], id: \.self) { level in
                            let isLevelActive = entry.isOn && abs(entry.dimming - level) <= 12
                            Button(intent: SetMoodLampWidgetBrightnessIntent(level: level)) {
                                Text("\(level)%")
                                    .font(.system(size: 10, weight: isLevelActive ? .heavy : .semibold, design: .rounded))
                                    .foregroundStyle(isLevelActive ? Color(red: 0.18, green: 0.1, blue: 0.05) : Color.white.opacity(0.85))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isLevelActive ? auraColor : Color.white.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Favorite Scenes
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("FAVOURITE SCENES")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.8))
                        Spacer()
                    }

                    let scenes = Array(entry.scenes.prefix(4))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(scenes) { scene in
                            let visual = visualForScene(id: scene.id, fallbackTitle: scene.title)
                            let isSceneActive = entry.isOn && entry.activeSceneId == scene.id
                            Button(intent: SetMoodLampWidgetSceneIntent(sceneId: scene.id)) {
                                HStack(spacing: 5) {
                                    Circle()
                                        .fill(LinearGradient(colors: visual.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 10, height: 10)
                                    Text(visual.title)
                                        .font(.system(size: 10, weight: isSceneActive ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isSceneActive ? .white : Color.white.opacity(0.85))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 7)
                                .frame(height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSceneActive ? visual.gradient.first?.opacity(0.25) ?? Color.white.opacity(0.12) : Color.white.opacity(0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(isSceneActive ? (visual.gradient.first ?? auraColor) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Large Widget

    private var largeWidget: some View {
        VStack(spacing: 16) {
            // Top Bar
            HStack(spacing: 8) {
                Image(systemName: "lamp.table.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(entry.isOn ? auraColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.lampName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(entry.isOn ? "Connected • \(entry.dimming)%" : "Turned Off")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(intent: ToggleMoodLampWidgetIntent()) {
                    HStack(spacing: 4) {
                        Image(systemName: entry.isOn ? "power" : "lightbulb.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(entry.isOn ? "Turn Off" : "Turn On")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(entry.isOn ? Color(red: 0.16, green: 0.1, blue: 0.05) : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(entry.isOn ? auraColor : Color.white.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

            // Hero Orb
            ZStack {
                if entry.isOn {
                    Circle()
                        .fill(auraColor.opacity(0.35))
                        .frame(width: 90, height: 90)
                        .blur(radius: 12)
                }

                Circle()
                    .fill(
                        entry.isOn
                            ? LinearGradient(
                                colors: [Color(red: 1.0, green: 0.82, blue: 0.45), Color(red: 0.98, green: 0.52, blue: 0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.white.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle()
                            .strokeBorder(entry.isOn ? Color.white.opacity(0.35) : Color.white.opacity(0.1), lineWidth: 1.5)
                    )

                VStack(spacing: 2) {
                    Text(entry.isOn ? "\(entry.dimming)%" : "OFF")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.isOn ? Color(red: 0.18, green: 0.1, blue: 0.05) : Color.white.opacity(0.6))
                    Text(entry.isOn ? "BRIGHT" : "TAP TO ON")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(entry.isOn ? Color(red: 0.25, green: 0.15, blue: 0.05).opacity(0.8) : Color.secondary)
                }
            }

            // Brightness Steppers & Quick Chips
            VStack(alignment: .leading, spacing: 6) {
                Text("BRIGHTNESS CONTROLS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))

                HStack(spacing: 6) {
                    Button(intent: StepMoodLampWidgetBrightnessIntent(delta: -20)) {
                        Image(systemName: "minus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)

                    ForEach([25, 50, 75, 100], id: \.self) { level in
                        let isLevelActive = entry.isOn && abs(entry.dimming - level) <= 12
                        Button(intent: SetMoodLampWidgetBrightnessIntent(level: level)) {
                            Text("\(level)%")
                                .font(.system(size: 11, weight: isLevelActive ? .heavy : .semibold, design: .rounded))
                                .foregroundStyle(isLevelActive ? Color(red: 0.18, green: 0.1, blue: 0.05) : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isLevelActive ? auraColor : Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button(intent: StepMoodLampWidgetBrightnessIntent(delta: 20)) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Scenes Grid
            VStack(alignment: .leading, spacing: 6) {
                Text("CURATED SCENES")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.8))

                let scenes = Array(entry.scenes.prefix(6))
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(scenes) { scene in
                        let visual = visualForScene(id: scene.id, fallbackTitle: scene.title)
                        let isSceneActive = entry.isOn && entry.activeSceneId == scene.id
                        Button(intent: SetMoodLampWidgetSceneIntent(sceneId: scene.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: visual.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(isSceneActive ? Color.white : visual.gradient.first ?? auraColor)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        Circle().fill(visual.gradient.first?.opacity(0.2) ?? Color.white.opacity(0.1))
                                    )

                                Text(visual.title)
                                    .font(.system(size: 11, weight: isSceneActive ? .bold : .semibold, design: .rounded))
                                    .foregroundStyle(isSceneActive ? .white : Color.white.opacity(0.9))
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                if isSceneActive {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(isSceneActive ? visual.gradient.first?.opacity(0.3) ?? Color.white.opacity(0.15) : Color.white.opacity(0.07))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(isSceneActive ? (visual.gradient.first ?? auraColor) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    // MARK: - Lock Screen Accessories

    private var accessoryCircularView: some View {
        ZStack {
            Gauge(value: Double(entry.isOn ? entry.dimming : 0), in: 0...100) {
                Image(systemName: entry.isOn ? "lightbulb.fill" : "lightbulb")
            } currentValueLabel: {
                Text(entry.isOn ? "\(entry.dimming)%" : "Off")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    private var accessoryRectangularView: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.lampName)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.isOn ? "On • \(entry.dimming)% Brightness" : "Turned Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var accessoryInlineView: some View {
        Label(
            "\(entry.lampName): \(entry.isOn ? "\(entry.dimming)%" : "Off")",
            systemImage: entry.isOn ? "lightbulb.fill" : "lightbulb"
        )
    }

    // MARK: - Setup Widget

    private var setupWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 38, height: 38)
                Image(systemName: "lamp.table.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            Text("Set up Mood Lamp")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Open the app to connect your light.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }
}

// MARK: - Home Screen Widget Configuration

struct MoodLampWidget: Widget {
    let kind = "MoodLampWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodLampWidgetProvider()) { entry in
            MoodLampWidgetView(entry: entry)
        }
        .configurationDisplayName("Mood Lamp")
        .description("Instant control, brightness adjustments, and curated scenes from your Home Screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

// MARK: - Control Center Widget (iOS 18)

struct ToggleMoodLampControlIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Mood Lamp"
    @Parameter(title: "Is On") var value: Bool

    func perform() async throws -> some IntentResult {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(value, forKey: "bulbOn")
        WidgetCenter.shared.reloadAllTimelines()

        try await WizClient.shared.setPilot(["state": value])
        return .result()
    }
}

struct MoodLampControlValueProvider: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        return defaults?.bool(forKey: "bulbOn") ?? false
    }
}

struct MoodLampControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "MoodLampControl", provider: MoodLampControlValueProvider()) { isOn in
            ControlWidgetToggle(
                "Mood Lamp",
                isOn: isOn,
                action: ToggleMoodLampControlIntent()
            ) { isTurnedOn in
                Label(isTurnedOn ? "On" : "Off", systemImage: isTurnedOn ? "lightbulb.fill" : "lightbulb")
                    .tint(.orange)
            }
        }
        .displayName("Mood Lamp")
        .description("Toggle your Mood Lamp on or off.")
    }
}

// MARK: - Widget Bundle

@main
struct MoodLampWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodLampWidget()
        MoodLampControlWidget()
    }
}
