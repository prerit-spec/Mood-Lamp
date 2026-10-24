import AppIntents
import SwiftUI
import WidgetKit

private let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"

struct MoodLampWidgetEntry: TimelineEntry {
    let date: Date
    let isConfigured: Bool
    let isOn: Bool
}

struct MoodLampWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoodLampWidgetEntry {
        MoodLampWidgetEntry(date: .now, isConfigured: true, isOn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MoodLampWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoodLampWidgetEntry>) -> Void) {
        let entry = makeEntry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60))))
    }

    private func makeEntry() -> MoodLampWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        return MoodLampWidgetEntry(
            date: .now,
            isConfigured: !(defaults?.string(forKey: "bulbIp") ?? "").isEmpty,
            isOn: defaults?.bool(forKey: "bulbOn") ?? false
        )
    }
}

struct ToggleMoodLampWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Mood Lamp"

    func perform() async throws -> some IntentResult {
        let lamp = await WizClient.shared
        let pilot = try await lamp.getPilot()
        guard let currentState = pilot["state"] as? Bool else { throw WizError.badReply }
        try await lamp.setPilot(["state": !currentState])
        return .result()
    }
}

struct SetMoodLampWidgetSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Mood Lamp scene"

    @Parameter(title: "Scene ID") var sceneId: Int

    init() {
        self.sceneId = 6
    }

    init(sceneId: Int) {
        self.sceneId = sceneId
    }

    func perform() async throws -> some IntentResult {
        try await WizClient.shared.setPilot(["state": true, "sceneId": sceneId])
        return .result()
    }
}

private enum MoodLampWidgetScene: Int, CaseIterable, Identifiable {
    case cozy = 6
    case nightLight = 14
    case focus = 15
    case relax = 16

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cozy: "Cozy"
        case .nightLight: "Night light"
        case .focus: "Focus"
        case .relax: "Relax"
        }
    }
}

struct MoodLampWidgetView: View {
    let entry: MoodLampWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.isConfigured {
                if family == .systemSmall {
                    smallWidget
                } else {
                    mediumWidget
                }
            } else {
                setupWidget
            }
        }
        .containerBackground(Color(red: 0.12, green: 0.09, blue: 0.08), for: .widget)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Mood Lamp", systemImage: entry.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.headline)
                .foregroundStyle(entry.isOn ? Color.orange : Color.white)
            Spacer(minLength: 0)
            Button(intent: ToggleMoodLampWidgetIntent()) {
                Label(entry.isOn ? "Turn Off" : "Turn On",
                      systemImage: entry.isOn ? "power" : "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(entry.isOn ? .orange : .white.opacity(0.2))
        }
        .padding()
    }

    private var mediumWidget: some View {
        HStack(spacing: 16) {
            Image(systemName: entry.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 42))
                .foregroundStyle(entry.isOn ? Color.orange : Color.white.opacity(0.55))
                .frame(width: 58)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Mood Lamp")
                        .font(.headline)
                    Spacer(minLength: 4)
                    Text(entry.isOn ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(MoodLampWidgetScene.allCases) { scene in
                        Button(intent: SetMoodLampWidgetSceneIntent(sceneId: scene.id)) {
                            Text(scene.title)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }
                Button(intent: ToggleMoodLampWidgetIntent()) {
                    Label(entry.isOn ? "Turn Off" : "Turn On",
                          systemImage: entry.isOn ? "power" : "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(entry.isOn ? .orange : .white.opacity(0.2))
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var setupWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Set up Mood Lamp")
                .font(.headline)
            Text("Open the app and add your bulb.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct MoodLampWidget: Widget {
    let kind = "MoodLampWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MoodLampWidgetProvider()) { entry in
            MoodLampWidgetView(entry: entry)
        }
        .configurationDisplayName("Mood Lamp")
        .description("Check your lamp, set a scene, or turn it on or off.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MoodLampWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodLampWidget()
    }
}
