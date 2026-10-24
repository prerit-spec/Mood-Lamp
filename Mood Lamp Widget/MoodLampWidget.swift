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
            VStack(alignment: .leading, spacing: 5) {
                Text("Mood Lamp")
                    .font(.headline)
                Text(entry.isOn ? "On" : "Off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button(intent: ToggleMoodLampWidgetIntent()) {
                    Label(entry.isOn ? "Turn Off" : "Turn On",
                          systemImage: entry.isOn ? "power" : "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
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
        .description("See your lamp's status and turn it on or off.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MoodLampWidgetBundle: WidgetBundle {
    var body: some Widget {
        MoodLampWidget()
    }
}
