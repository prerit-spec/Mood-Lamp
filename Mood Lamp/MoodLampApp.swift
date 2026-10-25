import Combine
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

// MARK: - App Entry Point

@main
struct MoodLampApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Colour helpers

func kelvinColor(_ kelvin: Double) -> Color {
    let k = kelvin / 100
    let r: Double = k <= 66 ? 255 : 329.698727446 * pow(k - 60, -0.1332047592)
    let g: Double = k <= 66 ? 99.4708025861 * log(k) - 161.1195681661 : 288.1221695283 * pow(k - 60, -0.0755148492)
    let b: Double = k >= 66 ? 255 : (k <= 19 ? 0 : 138.5177312231 * log(k - 10) - 305.0447927307)
    func c(_ v: Double) -> Double { min(255, max(0, v)) / 255 }
    return Color(red: c(r), green: c(g), blue: c(b))
}

func rgbFromHS(_ h: Double, _ s: Double) -> (Int, Int, Int) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    PlatformColor(hue: h / 360, saturation: s / 100, brightness: 1, alpha: 1).getRed(&r, green: &g, blue: &b, alpha: &a)
    return (Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}

// MARK: - Haptics

enum Haptics {
    #if canImport(UIKit)
    nonisolated static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    nonisolated static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    nonisolated static func soft() { UISelectionFeedbackGenerator().selectionChanged() }
    #else
    nonisolated static func light() {}
    nonisolated static func medium() {}
    nonisolated static func soft() {}
    #endif
}

// MARK: - Model

@MainActor
final class MoodLampModel: ObservableObject {
    enum Mode { case white, color }

    @Published var ip = WizClient.shared.ip
    @Published var on = false
    @Published var dimming = 80.0
    @Published var mode: Mode = .white
    @Published var temp = 2700.0
    @Published var hue = 30.0
    @Published var sat = 100.0
    @Published var scene: MoodLampScene?
    @Published var error: String?
    @Published var reachable = true
    @Published var hasLoaded = false
    @Published var lastPollError: String?
    @Published var showToast = false
    @Published var toastMessage = ""

    private var failures = 0
    private var sendTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var toastDismissTask: Task<Void, Never>?
    private var lastUserChange = Date.distantPast

    var glow: Color {
        guard on && reachable else { return Color(white: 0.22) }
        return mode == .color ? Color(hue: hue / 360, saturation: sat / 100, brightness: 1) : kelvinColor(temp)
    }

    var lampName: String {
        LampStore.shared.activeLamp?.name ?? "Mood Lamp"
    }

    // MARK: Save IP

    func saveIP(_ value: String, name: String = "Mood Lamp") {
        ip = value.trimmingCharacters(in: .whitespaces)
        WizClient.shared.ip = ip
        WizClient.shared.mac = ""
        hasLoaded = false; failures = 0

        // Create or update lamp in store
        let store = LampStore.shared
        if let existing = store.lamps.first(where: { $0.ip == ip }) {
            var updated = existing
            if !name.isEmpty { updated.name = name }
            store.update(updated)
            store.setActive(updated.id)
        } else {
            let lamp = SavedLamp(name: name.isEmpty ? "Mood Lamp" : name, ip: ip)
            store.add(lamp)
            store.setActive(lamp.id)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: Switch Lamp

    func switchToLamp(_ lamp: SavedLamp) {
        ip = lamp.ip
        WizClient.shared.ip = lamp.ip
        WizClient.shared.mac = lamp.mac
        LampStore.shared.setActive(lamp.id)
        hasLoaded = false; failures = 0
        on = false; reachable = true; error = nil; lastPollError = nil; scene = nil
        Task { await refresh(); startPolling() }
    }

    // MARK: Toast

    private func showToastError(_ message: String) {
        toastMessage = message
        showToast = true
        toastDismissTask?.cancel()
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            showToast = false
        }
    }

    // Wait briefly so dragging a slider sends the latest value, not every value.
    private func push(_ params: [String: Any]) {
        lastUserChange = Date()
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            do { try await WizClient.shared.setPilot(params); ip = WizClient.shared.ip; error = nil }
            catch { showToastError(error.localizedDescription) }
        }
    }

    func refresh(resilient: Bool = true, quiet: Bool = false) async {
        guard !ip.isEmpty else { return }
        do {
            let p = try await WizClient.shared.getPilot(resilient: resilient)
            ip = WizClient.shared.ip
            reachable = true
            hasLoaded = true
            failures = 0
            lastPollError = nil
            on = p["state"] as? Bool ?? false
            if let d = p["dimming"] as? Int { dimming = Double(d) }
            if let id = p["sceneId"] as? Int, id > 0 { scene = MoodLampScene.allCases.first { $0.sceneId == id } } else { scene = nil }
            if let t = p["temp"] as? Int { mode = .white; temp = Double(t) }
            else if let r = p["r"] as? Int, let g = p["g"] as? Int, let b = p["b"] as? Int {
                mode = .color
                var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
                PlatformColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
                    .getHue(&h, saturation: &s, brightness: &v, alpha: &a)
                hue = Double(h) * 360; sat = Double(s) * 100
            }
            error = nil
        } catch {
            failures += 1
            hasLoaded = true
            lastPollError = error.localizedDescription
            // One lost packet must not flip the screen to offline: background polls have to fail twice in a row.
            if !quiet || failures >= 2 { reachable = false }
            if !quiet { showToastError(error.localizedDescription) }
        }
    }

    /// While the app is open, ask the lamp for its state every 2 seconds so manual or WiZ-app changes show up.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if Task.isCancelled { break }
                if Date().timeIntervalSince(lastUserChange) < 2 { continue }   // don't fight the user's own taps
                await refresh(resilient: false, quiet: true)
            }
        }
    }
    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func togglePower() {
        Haptics.medium()
        guard reachable else { Task { await refresh() }; return }   // tapping while offline retries
        on.toggle(); push(["state": on])
    }
    func brightnessChanged() { on = true; push(["state": true, "dimming": Int(dimming)]) }
    func tempChanged() { on = true; scene = nil; push(["state": true, "temp": Int(temp), "dimming": Int(dimming)]) }
    func colorChanged() {
        on = true; scene = nil
        let (r, g, b) = rgbFromHS(hue, sat)
        push(["state": true, "r": r, "g": g, "b": b, "dimming": Int(dimming)])
    }
    func setMode(_ m: Mode) {
        mode = m; scene = nil
        if m == .color { if sat < 30 { sat = 100 }; colorChanged() } else { tempChanged() }
    }
    func choose(_ s: MoodLampScene) {
        Haptics.soft()
        scene = s; on = true; push(["state": true, "sceneId": s.sceneId, "dimming": Int(dimming)])
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var m = MoodLampModel()
    @StateObject private var store = LampStore.shared
    @State private var showSetup = false
    @State private var showSettings = false
    @State private var showSleepTimerSheet = false
    @State private var breathe = false
    @State private var sleepTimerEnd: Date?
    @State private var sleepTimerTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase

    private var lit: Bool { m.on && m.reachable }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                if !m.reachable, let detail = m.lastPollError {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                orb
                quickActions
                controls
                scenes
            }
            .padding(20)
        }
        .overlay(alignment: .top) { toastOverlay }
        .background(gradientBackground)
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.3), value: m.on)
        .sheet(isPresented: $showSetup) { SetupView(m: m) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showSleepTimerSheet) { sleepTimerSheet }
        .task { if m.ip.isEmpty { showSetup = true } else { await m.refresh(); m.startPolling() } }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await m.refresh(); m.startPolling() } } else { m.stopPolling() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if store.lamps.count > 1 {
                    Menu {
                        ForEach(store.lamps) { lamp in
                            Button {
                                m.switchToLamp(lamp)
                            } label: {
                                HStack {
                                    Text(lamp.name)
                                    if lamp.id == store.activeLampId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(m.lampName).font(.headline)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(m.ip.isEmpty ? "No Mood Lamp selected" : (m.reachable ? "Mood Lamp at \(m.ip)" : "Mood Lamp offline"))
                        .foregroundStyle(m.reachable ? Color.secondary : Color.red)
                        .font(.subheadline)
                }
                if !m.reachable && store.lamps.count > 1 {
                    Text(m.reachable ? "" : "Offline")
                        .font(.subheadline).foregroundStyle(.red)
                }
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Animated Orb

    private var orb: some View {
        Button { m.togglePower() } label: {
            ZStack {
                Circle().fill(m.glow)
                    .shadow(color: m.glow.opacity(lit ? 0.6 : 0), radius: lit ? (breathe ? 60 : 30) : 0)
                    .brightness(lit ? (m.dimming / 100 - 0.8) * 0.4 : 0)
                Text(orbLabel)
                    .font(.system(size: lit ? 46 : 26, weight: lit ? .bold : .medium, design: .rounded))
                    .foregroundStyle(lit ? Color.black.opacity(0.7) : .secondary)
            }
            .frame(width: 240, height: 240)
            .scaleEffect(lit && breathe ? 1.03 : 1.0)
            .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: breathe)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.on ? "Turn off" : "Turn on")
        .onChange(of: lit) { _, isLit in
            if isLit { breathe = true } else { breathe = false }
        }
        .onAppear { if lit { breathe = true } }
    }

    private var orbLabel: String {
        if !m.hasLoaded && !m.ip.isEmpty { return "Connecting" }
        if !m.reachable { return "Offline" }
        if m.on { return "\(Int(m.dimming))%" }
        return "Off"
    }

    // MARK: Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            quickActionButton(
                icon: "sun.horizon.fill",
                label: "Adaptive",
                active: AdaptiveLightingManager.shared.enabled
            ) { toggleAdaptive() }

            #if canImport(MediaPlayer)
            quickActionButton(
                icon: "music.note",
                label: "Music Mood",
                active: MusicMoodManager.shared.isActive
            ) { toggleMusicMood() }
            #endif

            quickActionButton(
                icon: "timer",
                label: sleepTimerLabel,
                active: sleepTimerEnd != nil
            ) { showSleepTimerSheet = true }
        }
    }

    private var sleepTimerLabel: String {
        guard let end = sleepTimerEnd else { return "Sleep Timer" }
        let remaining = end.timeIntervalSinceNow
        if remaining <= 0 { return "Sleep Timer" }
        let mins = Int(remaining) / 60
        if mins >= 60 {
            return "\(mins / 60)h \(mins % 60)m"
        }
        return "\(mins)m"
    }

    private func quickActionButton(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.soft()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(active ? Color.orange.opacity(0.2) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(active ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: Adaptive & Music Mood

    private func toggleAdaptive() {
        let manager = AdaptiveLightingManager.shared
        if manager.enabled {
            manager.stop()
        } else {
            manager.start { temp in
                self.m.temp = temp
                self.m.mode = .white
                self.m.tempChanged()
            }
        }
    }

    #if canImport(MediaPlayer)
    private func toggleMusicMood() {
        let manager = MusicMoodManager.shared
        if manager.isActive {
            manager.stop()
        } else {
            manager.start { hue, sat in
                self.m.hue = hue
                self.m.sat = sat
                self.m.mode = .color
                self.m.colorChanged()
            }
        }
    }
    #endif

    // MARK: Sleep Timer

    private func startSleepTimer(minutes: Int) {
        sleepTimerTask?.cancel()
        sleepTimerEnd = Date().addingTimeInterval(Double(minutes * 60))
        sleepTimerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            try? await WizClient.shared.setPilot(["state": false])
            await m.refresh()
            sleepTimerEnd = nil
        }
    }

    private func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEnd = nil
    }

    private var sleepTimerSheet: some View {
        NavigationStack {
            List {
                if sleepTimerEnd != nil {
                    Section {
                        Button("Cancel Timer", role: .destructive) {
                            cancelSleepTimer()
                            showSleepTimerSheet = false
                        }
                    }
                }
                Section("Set Sleep Timer") {
                    ForEach([15, 30, 45, 60, 120], id: \.self) { mins in
                        Button {
                            startSleepTimer(minutes: mins)
                            showSleepTimerSheet = false
                        } label: {
                            HStack {
                                Text(mins < 60 ? "\(mins) minutes" : (mins == 60 ? "1 hour" : "2 hours"))
                                Spacer()
                                Image(systemName: "moon.zzz.fill").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("The lamp will turn off after the selected time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sleep Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSleepTimerSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            labeled("Brightness", "\(Int(m.dimming))%") {
                Slider(value: Binding(get: { m.dimming }, set: { newVal in
                    let old = m.dimming
                    m.dimming = newVal
                    m.brightnessChanged()
                    // Haptic at endpoints
                    if (old > 10 && newVal <= 10) || (old < 100 && newVal >= 100) {
                        Haptics.soft()
                    }
                }), in: 10...100, step: 1)
            }
            Picker("Mode", selection: Binding(get: { m.mode }, set: { m.setMode($0) })) {
                Text("White").tag(MoodLampModel.Mode.white)
                Text("Color").tag(MoodLampModel.Mode.color)
            }
            .pickerStyle(.segmented)

            if m.mode == .white {
                labeled("Warmth", "\(Int(m.temp)) K") {
                    Slider(value: Binding(get: { m.temp }, set: { newVal in
                        let old = m.temp
                        m.temp = newVal
                        m.tempChanged()
                        if (old > 2200 && newVal <= 2200) || (old < 6500 && newVal >= 6500) {
                            Haptics.soft()
                        }
                    }), in: 2200...6500, step: 100)
                }
            } else {
                ColorWheel(hue: m.hue, sat: m.sat) { h, s in
                    m.hue = h; m.sat = s; m.colorChanged()
                }
                .frame(width: 250, height: 250)
                .frame(maxWidth: .infinity)

                // Hex colour display
                HStack {
                    Text(hexColorString(hue: m.hue, sat: m.sat))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Haptics.soft()
                        LampStore.shared.saveColour(hue: m.hue, sat: m.sat)
                    } label: {
                        Label("Save Colour", systemImage: "heart.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.orange)
                }

                if !LampStore.shared.savedColours.isEmpty {
                    SavedColoursStrip(colours: LampStore.shared.savedColours) { h, s in
                        m.hue = h; m.sat = s; m.colorChanged()
                    } onRemove: { id in
                        LampStore.shared.removeColour(id: id)
                    }
                }

                Text("Drag around the wheel. The center is white, the edge is the strongest colour.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .opacity(lit ? 1 : 0.4)
        .disabled(!lit)
    }

    private func hexColorString(hue: Double, sat: Double) -> String {
        let (r, g, b) = rgbFromHS(hue, sat)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // MARK: Scenes

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scenes").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(LampStore.shared.sortedScenes, id: \.self) { s in
                    Button { m.choose(s) } label: {
                        VStack(spacing: 0) {
                            // Colour swatch bar
                            HStack(spacing: 0) {
                                ForEach(Array(s.colors.enumerated()), id: \.offset) { _, color in
                                    color.frame(maxWidth: .infinity, maxHeight: 3)
                                }
                            }

                            Text(s.label).font(.subheadline)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .background(m.scene == s ? Color.white : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(m.scene == s ? Color.black : Color.white)
                        .overlay(alignment: .topTrailing) {
                            if LampStore.shared.isFavourite(s) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                    .padding(6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            LampStore.shared.toggleFavourite(s)
                        } label: {
                            Label(
                                LampStore.shared.isFavourite(s) ? "Remove Favourite" : "Add Favourite",
                                systemImage: LampStore.shared.isFavourite(s) ? "star.slash" : "star.fill"
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .opacity(lit ? 1 : 0.4)
        .disabled(!lit)
    }

    // MARK: Toast Overlay

    @ViewBuilder
    private var toastOverlay: some View {
        if m.showToast {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(m.toastMessage)
                    .font(.subheadline)
                    .lineLimit(2)
                Spacer()
                Button {
                    m.showToast = false
                    Task { await m.refresh() }
                } label: {
                    Text("Retry").font(.subheadline.bold())
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: m.showToast)
        }
    }

    // MARK: Background Gradient

    private var gradientBackground: some View {
        LinearGradient(colors: [m.glow.opacity(m.on ? 0.28 : 0.05), Color(red: 0.08, green: 0.07, blue: 0.06)],
                       startPoint: .top, endPoint: .center).ignoresSafeArea()
            .background(Color(red: 0.08, green: 0.07, blue: 0.06).ignoresSafeArea())
    }

    // MARK: Helpers

    private func labeled<C: View>(_ title: String, _ value: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.subheadline)
            content()
        }
    }
}

// MARK: - Colour Wheel

/// Angle around the wheel picks the colour, distance from the centre picks how strong it is.
struct ColorWheel: View {
    let hue: Double   // 0...360
    let sat: Double   // 0...100
    let onChange: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let angle = hue * .pi / 180
            let dist = sat / 100 * radius
            ZStack {
                Circle().fill(AngularGradient(
                    gradient: Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) }),
                    center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle()
                    .fill(Color(hue: hue / 360, saturation: sat / 100, brightness: 1))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 4))
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.4), radius: 4)
                    .offset(x: cos(angle) * dist, y: sin(angle) * dist)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let dx = g.location.x - radius
                    let dy = g.location.y - radius
                    var deg = atan2(dy, dx) * 180 / .pi
                    if deg < 0 { deg += 360 }
                    let d = min(sqrt(dx * dx + dy * dy), radius)
                    onChange(deg, d / radius * 100)
                }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colour wheel. Hue \(Int(hue)) degrees, saturation \(Int(sat)) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                let newHue = (hue + 15).truncatingRemainder(dividingBy: 360)
                onChange(newHue, sat)
            case .decrement:
                var newHue = hue - 15
                if newHue < 0 { newHue += 360 }
                onChange(newHue, sat)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - Saved Colours Strip

struct SavedColoursStrip: View {
    let colours: [SavedColour]
    let onSelect: (Double, Double) -> Void
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(colours) { colour in
                    Circle()
                        .fill(Color(hue: colour.hue / 360, saturation: colour.sat / 100, brightness: 1))
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .shadow(color: Color(hue: colour.hue / 360, saturation: colour.sat / 100, brightness: 1).opacity(0.4), radius: 4)
                        .onTapGesture {
                            Haptics.soft()
                            onSelect(colour.hue, colour.sat)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                onRemove(colour.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Setup View

struct SetupView: View {
    @ObservedObject var m: MoodLampModel
    @State private var text = ""
    @State private var name = ""
    @State private var scanning = false
    @State private var discovered: [(ip: String, mac: String)] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Mood Lamp IP address") {
                    TextField("192.168.1.50", text: $text)
                    #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                    #endif
                        .autocorrectionDisabled()
                    TextField("Lamp name (optional)", text: $name)
                    #if os(iOS)
                        .textInputAutocapitalization(.words)
                    #endif
                }

                Section {
                    Button {
                        scanNetwork()
                    } label: {
                        HStack {
                            Label("Scan Network", systemImage: "antenna.radiowaves.left.and.right")
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
                                text = lamp.ip
                                if name.isEmpty { name = "Mood Lamp" }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lamp.ip).font(.body)
                                    if !lamp.mac.isEmpty {
                                        Text("MAC: \(lamp.mac)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Text("Find your Mood Lamp in the WiZ app's settings or your router's list of connected devices. Make sure Local integrations is on in the WiZ app.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose Mood Lamp")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        m.saveIP(text, name: name.isEmpty ? "Mood Lamp" : name)
                        dismiss()
                        Task { await m.refresh() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = m.ip; name = LampStore.shared.activeLamp?.name ?? "" }
        }
        .presentationDetents([.medium, .large])
    }

    private func scanNetwork() {
        scanning = true
        discovered = []
        Task {
            let results = await WizClient.shared.scan()
            discovered = results
            scanning = false
        }
    }
}
