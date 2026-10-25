import Combine
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = LampStore.shared
    @ObservedObject private var scheduleManager = ScheduleManager.shared
    @ObservedObject private var adaptiveManager = AdaptiveLightingManager.shared

    @State private var showAddLamp = false
    @State private var showAddSchedule = false

    var body: some View {
        NavigationStack {
            List {
                // SECTION: Lamps
                Section {
                    ForEach(store.lamps) { lamp in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(lamp.name)
                                    .font(.headline)
                                Text(lamp.ip)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if lamp.id == store.activeLampId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.light()
                            store.setActive(lamp.id)
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            store.remove(id: store.lamps[i].id)
                        }
                    }

                    Button {
                        showAddLamp = true
                    } label: {
                        Label("Add Mood Lamp", systemImage: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Your Lamps")
                } footer: {
                    Text("Tap a lamp to activate it, or swipe to remove.")
                }

                // SECTION: Favourite Scenes
                Section("Favourite Scenes") {
                    Text("Long-press any scene on the main screen to toggle favourites. Favourites appear first and sync to your widget.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !store.favouriteSceneRawValues.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MoodLampScene.allCases.filter { store.isFavourite($0) }, id: \.self) { scene in
                                    HStack(spacing: 6) {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.yellow)
                                        Text(scene.label)
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                // SECTION: Schedules
                Section {
                    ForEach(scheduleManager.schedules) { schedule in
                        ScheduleRow(schedule: schedule)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            scheduleManager.removeSchedule(id: scheduleManager.schedules[i].id)
                        }
                    }

                    Button {
                        showAddSchedule = true
                    } label: {
                        Label("Add Schedule", systemImage: "plus.circle.fill")
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Schedules & Timers")
                } footer: {
                    Text("Schedules send reminders through system notifications.")
                }

                // SECTION: Adaptive Lighting
                Section {
                    Toggle("Adaptive Lighting", isOn: $adaptiveManager.enabled)
                        .tint(.orange)
                    Text("Automatically shifts colour temperature throughout the day from morning warm white to midday daylight and cozy evening.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Circadian Rhythm")
                }

                // SECTION: Automations
                Section("Siri & Shortcuts") {
                    NavigationLink {
                        AutomationsGalleryView()
                    } label: {
                        Label("Automation Ideas", systemImage: "sparkles")
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddLamp) {
                AddLampSheet()
            }
            .sheet(isPresented: $showAddSchedule) {
                AddScheduleView()
            }
        }
    }
}

// MARK: - Schedule Row

struct ScheduleRow: View {
    let schedule: LampSchedule

    private var timeString: String {
        let hour = schedule.hour
        let minute = String(format: "%02d", schedule.minute)
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):\(minute) \(period)"
    }

    private var repeatString: String {
        if schedule.repeatDays.isEmpty {
            return "Once"
        }
        if schedule.repeatDays.count == 7 {
            return "Every day"
        }
        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return schedule.repeatDays.sorted().compactMap { $0 < dayNames.count ? dayNames[$0] : nil }.joined(separator: ", ")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.title3.weight(.semibold))
                    Text(schedule.action.label)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(schedule.action == .turnOn ? Color.orange.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
                        .foregroundStyle(schedule.action == .turnOn ? Color.orange : Color.secondary)
                }
                Text(schedule.label.isEmpty ? repeatString : "\(schedule.label) • \(repeatString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { schedule.enabled },
                set: { _ in
                    Haptics.light()
                    ScheduleManager.shared.toggleSchedule(id: schedule.id)
                }
            ))
            .labelsHidden()
            .tint(.orange)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Add Schedule View

struct AddScheduleView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var selectedDate = Date()
    @State private var action: ScheduleAction = .turnOn
    @State private var selectedDays: Set<Int> = []

    private let dayOptions: [(Int, String)] = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Time & Action") {
                    DatePicker("Time", selection: $selectedDate, displayedComponents: .hourAndMinute)
                    Picker("Action", selection: $action) {
                        ForEach(ScheduleAction.allCases, id: \.self) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Repeat") {
                    HStack {
                        ForEach(dayOptions, id: \.0) { day, name in
                            Button {
                                if selectedDays.contains(day) {
                                    selectedDays.remove(day)
                                } else {
                                    selectedDays.insert(day)
                                }
                            } label: {
                                Text(name)
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selectedDays.contains(day) ? Color.orange : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(selectedDays.contains(day) ? Color.black : Color.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Label") {
                    TextField("e.g. Wake up, Bedtime", text: $label)
                }
            }
            .navigationTitle("New Schedule")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: selectedDate)
        let minute = calendar.component(.minute, from: selectedDate)
        let schedule = LampSchedule(
            label: label.isEmpty ? action.label : label,
            hour: hour,
            minute: minute,
            action: action,
            repeatDays: selectedDays,
            enabled: true
        )
        ScheduleManager.shared.addSchedule(schedule)
        Task {
            await ScheduleManager.shared.requestPermission()
        }
        dismiss()
    }
}

// MARK: - Add Lamp Sheet

struct AddLampSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ip = ""
    @State private var scanning = false
    @State private var discovered: [(ip: String, mac: String)] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Lamp Details") {
                    TextField("Name (e.g. Bedroom)", text: $name)
                    TextField("IP Address (e.g. 192.168.1.50)", text: $ip)
                    #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                    #endif
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        scanNetwork()
                    } label: {
                        HStack {
                            Label("Scan Local Network", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if scanning {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(scanning)

                    if !discovered.isEmpty {
                        ForEach(discovered, id: \.ip) { lamp in
                            Button {
                                ip = lamp.ip
                                if name.isEmpty { name = "WiZ Lamp" }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lamp.ip)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("MAC: \(lamp.mac)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Auto-Discovery")
                } footer: {
                    Text("Make sure your device is on the same 2.4GHz Wi-Fi network and Local integrations is enabled in the WiZ app.")
                }
            }
            .navigationTitle("Add Mood Lamp")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanedIP = ip.trimmingCharacters(in: .whitespaces)
                        guard !cleanedIP.isEmpty else { return }
                        let lamp = SavedLamp(
                            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Mood Lamp" : name,
                            ip: cleanedIP
                        )
                        LampStore.shared.add(lamp)
                        dismiss()
                    }
                    .disabled(ip.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func scanNetwork() {
        scanning = true
        discovered = []
        Task {
            let found = await WizClient.shared.scan()
            discovered = found
            scanning = false
        }
    }
}

// MARK: - Automations Gallery

struct AutomationsGalleryView: View {
    private struct AutomationIdea: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: String
        let color: Color
    }

    private let ideas: [AutomationIdea] = [
        AutomationIdea(
            title: "Turn on at Sunset",
            description: "Automatically light up your lamp with a cozy warm glow as the sun goes down.",
            icon: "sunset.fill",
            color: .orange
        ),
        AutomationIdea(
            title: "Night Light at Bedtime",
            description: "Dim the lamp to 10% Night Light scene when your Sleep focus turns on.",
            icon: "moon.stars.fill",
            color: .indigo
        ),
        AutomationIdea(
            title: "Movie Time with Netflix",
            description: "When the TV or Netflix app opens, trigger the TV Time scene for ambient viewing.",
            icon: "tv.fill",
            color: .purple
        ),
        AutomationIdea(
            title: "Welcome Home",
            description: "Turn on the lamp automatically when you arrive at your home location.",
            icon: "house.fill",
            color: .green
        ),
        AutomationIdea(
            title: "Focus Mode for Work",
            description: "Switch to 6500K crisp daylight when you activate Work focus.",
            icon: "brain.head.profile",
            color: .blue
        )
    ]

    var body: some View {
        List {
            Section {
                Text("Mood Lamp provides native Siri Shortcuts for power, scenes, brightness, and colors. Use Apple's Shortcuts app to connect them to daily routines, NFC tags, or location triggers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Automation Ideas") {
                ForEach(ideas) { idea in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: idea.icon)
                                .font(.title2)
                                .foregroundStyle(idea.color)
                                .frame(width: 36, height: 36)
                                .background(idea.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(idea.title)
                                    .font(.headline)
                                Text(idea.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    #if canImport(UIKit)
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                    #elseif canImport(AppKit)
                    if let url = URL(string: "shortcuts://") {
                        NSWorkspace.shared.open(url)
                    }
                    #endif
                } label: {
                    Label("Open Apple Shortcuts App", systemImage: "arrow.up.forward.app")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Automations Gallery")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

