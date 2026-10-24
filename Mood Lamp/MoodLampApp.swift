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

    private var failures = 0
    private var sendTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastUserChange = Date.distantPast

    var glow: Color {
        guard on && reachable else { return Color(white: 0.22) }
        return mode == .color ? Color(hue: hue / 360, saturation: sat / 100, brightness: 1) : kelvinColor(temp)
    }

    func saveIP(_ value: String) {
        ip = value.trimmingCharacters(in: .whitespaces)
        WizClient.shared.ip = ip
        WizClient.shared.mac = ""
        hasLoaded = false; failures = 0
        WidgetCenter.shared.reloadAllTimelines()
    }

    // Wait briefly so dragging a slider sends the latest value, not every value.
    private func push(_ params: [String: Any]) {
        lastUserChange = Date()
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            do { try await WizClient.shared.setPilot(params); ip = WizClient.shared.ip; error = nil }
            catch { self.error = error.localizedDescription }
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
            if !quiet { self.error = error.localizedDescription }
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
    func choose(_ s: MoodLampScene) { scene = s; on = true; push(["state": true, "sceneId": s.sceneId, "dimming": Int(dimming)]) }
}

// MARK: - Screen

struct ContentView: View {
    @StateObject private var m = MoodLampModel()
    @State private var showSetup = false
    @Environment(\.scenePhase) private var phase

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                HStack {
                    Text(m.ip.isEmpty ? "No Mood Lamp selected" : (m.reachable ? "Mood Lamp at \(m.ip)" : "Mood Lamp offline")).foregroundStyle(m.reachable ? Color.secondary : Color.red)
                    Spacer()
                    Button("Change Mood Lamp") { showSetup = true }.foregroundStyle(.secondary)
                }
                .font(.subheadline)

                if !m.reachable, let detail = m.lastPollError {
                    Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                orb
                controls
                scenes

                if let e = m.error {
                    Text(e).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .background(
            LinearGradient(colors: [m.glow.opacity(m.on ? 0.28 : 0.05), Color(red: 0.08, green: 0.07, blue: 0.06)],
                           startPoint: .top, endPoint: .center).ignoresSafeArea()
                .background(Color(red: 0.08, green: 0.07, blue: 0.06).ignoresSafeArea())
        )
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.3), value: m.on)
        .sheet(isPresented: $showSetup) { SetupView(m: m) }
        .task { if m.ip.isEmpty { showSetup = true } else { await m.refresh(); m.startPolling() } }
        .onChange(of: phase) { _, p in
            if p == .active { Task { await m.refresh(); m.startPolling() } } else { m.stopPolling() }
        }
    }

    private var lit: Bool { m.on && m.reachable }

    private var orb: some View {
        Button { m.togglePower() } label: {
            ZStack {
                Circle().fill(m.glow)
                    .shadow(color: m.glow.opacity(lit ? 0.6 : 0), radius: 50)
                    .brightness(lit ? (m.dimming / 100 - 0.8) * 0.4 : 0)
                Text(!m.hasLoaded && !m.ip.isEmpty ? "Connecting" : (!m.reachable ? "Offline" : (m.on ? "\(Int(m.dimming))%" : "Off")))
                    .font(.system(size: lit ? 46 : 26, weight: lit ? .bold : .medium, design: .rounded))
                    .foregroundStyle(lit ? Color.black.opacity(0.7) : .secondary)
            }
            .frame(width: 240, height: 240)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(m.on ? "Turn off" : "Turn on")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            labeled("Brightness", "\(Int(m.dimming))%") {
                Slider(value: Binding(get: { m.dimming }, set: { m.dimming = $0; m.brightnessChanged() }), in: 10...100, step: 1)
            }
            Picker("Mode", selection: Binding(get: { m.mode }, set: { m.setMode($0) })) {
                Text("White").tag(MoodLampModel.Mode.white)
                Text("Color").tag(MoodLampModel.Mode.color)
            }
            .pickerStyle(.segmented)

            if m.mode == .white {
                labeled("Warmth", "\(Int(m.temp)) K") {
                    Slider(value: Binding(get: { m.temp }, set: { m.temp = $0; m.tempChanged() }), in: 2200...6500, step: 100)
                }
            } else {
                ColorWheel(hue: m.hue, sat: m.sat) { h, s in
                    m.hue = h; m.sat = s; m.colorChanged()
                }
                .frame(width: 250, height: 250)
                .frame(maxWidth: .infinity)
                Text("Drag around the wheel. The center is white, the edge is the strongest colour.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .opacity(lit ? 1 : 0.4)
        .disabled(!lit)
    }

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scenes").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(MoodLampScene.allCases, id: \.self) { s in
                    Button { m.choose(s) } label: {
                        Text(s.label).font(.subheadline)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(m.scene == s ? Color.white : Color.white.opacity(0.08), in: Capsule())
                            .foregroundStyle(m.scene == s ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
        .opacity(lit ? 1 : 0.4)
        .disabled(!lit)
    }

    private func labeled<C: View>(_ title: String, _ value: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value) }.font(.subheadline)
            content()
        }
    }
}

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
        .accessibilityLabel("Colour wheel")
    }
}

struct SetupView: View {
    @ObservedObject var m: MoodLampModel
    @State private var text = ""
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Mood Lamp") {
                        m.saveIP(text); dismiss()
                        Task { await m.refresh() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { text = m.ip }
        }
        .presentationDetents([.medium])
    }
}
