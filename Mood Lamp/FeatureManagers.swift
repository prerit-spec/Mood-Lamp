import Combine
import Foundation
import SwiftUI
import UserNotifications
#if canImport(MediaPlayer)
import MediaPlayer
#endif

// MARK: - Schedule Models

enum ScheduleAction: String, Codable, CaseIterable {
    case turnOn
    case turnOff

    var label: String {
        switch self {
        case .turnOn: return "Turn On"
        case .turnOff: return "Turn Off"
        }
    }
}

struct LampSchedule: Identifiable, Codable {
    let id: UUID
    var label: String
    var hour: Int       // 0-23
    var minute: Int     // 0-59
    var action: ScheduleAction
    var repeatDays: Set<Int>   // 1=Sun...7=Sat, empty = one-shot
    var enabled: Bool

    init(id: UUID = UUID(), label: String = "Schedule", hour: Int = 8, minute: Int = 0, action: ScheduleAction = .turnOn, repeatDays: Set<Int> = [], enabled: Bool = true) {
        self.id = id
        self.label = label
        self.hour = hour
        self.minute = minute
        self.action = action
        self.repeatDays = repeatDays
        self.enabled = enabled
    }
}

// MARK: - ScheduleManager

@MainActor
final class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    private static let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"
    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
    }

    private static let schedulesKey = "lampSchedules"
    private static let categoryIdentifier = "LAMP_SCHEDULE"

    @Published var schedules: [LampSchedule] {
        didSet { saveSchedules(); rescheduleNotifications() }
    }

    private init() {
        if let data = Self.sharedDefaults.data(forKey: Self.schedulesKey),
           let decoded = try? JSONDecoder().decode([LampSchedule].self, from: data) {
            self.schedules = decoded
        } else {
            self.schedules = []
        }
    }

    // MARK: - Public API

    func addSchedule(_ schedule: LampSchedule) {
        schedules.append(schedule)
    }

    func removeSchedule(id: UUID) {
        schedules.removeAll(where: { $0.id == id })
    }

    func toggleSchedule(id: UUID) {
        if let index = schedules.firstIndex(where: { $0.id == id }) {
            schedules[index].enabled.toggle()
        }
    }

    func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Persistence

    private func saveSchedules() {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        Self.sharedDefaults.set(data, forKey: Self.schedulesKey)
    }

    // MARK: - Notification Scheduling

    private func rescheduleNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            let lampRequests = requests.filter { $0.content.categoryIdentifier == Self.categoryIdentifier }
            let idsToRemove = lampRequests.map { $0.identifier }
            if !idsToRemove.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: idsToRemove)
            }

            for schedule in schedules where schedule.enabled {
                let content = UNMutableNotificationContent()
                content.title = "Mood Lamp"
                content.body = "\(schedule.label): \(schedule.action.label)"
                content.sound = .default
                content.categoryIdentifier = Self.categoryIdentifier

                if schedule.repeatDays.isEmpty {
                    // One-shot: fire at the specified hour/minute
                    var dateComponents = DateComponents()
                    dateComponents.hour = schedule.hour
                    dateComponents.minute = schedule.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
                    let request = UNNotificationRequest(identifier: schedule.id.uuidString, content: content, trigger: trigger)
                    try? await center.add(request)
                } else {
                    // Repeating: one notification request per day of the week
                    for day in schedule.repeatDays {
                        var dateComponents = DateComponents()
                        dateComponents.weekday = day
                        dateComponents.hour = schedule.hour
                        dateComponents.minute = schedule.minute
                        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                        let identifier = "\(schedule.id.uuidString)-\(day)"
                        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
                        try? await center.add(request)
                    }
                }
            }
        }
    }
}

// MARK: - AdaptiveLightingManager

@MainActor
final class AdaptiveLightingManager: ObservableObject {
    static let shared = AdaptiveLightingManager()

    private static let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"
    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
    }

    private static let enabledKey = "adaptiveLightingEnabled"

    @Published var enabled: Bool {
        didSet { Self.sharedDefaults.set(enabled, forKey: Self.enabledKey) }
    }

    private var timerTask: Task<Void, Never>?

    /// Recommended colour temperature (2200-6500K) based on the current time of day.
    /// Uses smooth sinusoidal interpolation between time-of-day segments.
    var recommendedTemp: Double {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let fractionalHour = Double(hour) + Double(minute) / 60.0

        // Time segments with sinusoidal interpolation:
        // 6:00 - 9:00  : sunrise warmup     2700 → 4500
        // 9:00 - 17:00 : daylight           5500 → 6500 (peak around midday)
        // 17:00 - 20:00: sunset cooldown    4500 → 2700
        // 20:00 - 6:00 : evening/night      2200 → 2700 (lowest around midnight)

        if fractionalHour >= 6.0 && fractionalHour < 9.0 {
            // Sunrise warmup: 2700 → 4500
            let t = (fractionalHour - 6.0) / 3.0
            return smoothInterpolate(from: 2700, to: 4500, t: t)
        } else if fractionalHour >= 9.0 && fractionalHour < 17.0 {
            // Daylight: bell curve peaking at 6500 around 13:00
            let t = (fractionalHour - 9.0) / 8.0
            // Use sine to create a smooth peak at midpoint
            let factor = sin(t * .pi)
            return 5500 + factor * 1000  // 5500 to 6500 and back
        } else if fractionalHour >= 17.0 && fractionalHour < 20.0 {
            // Sunset cooldown: 4500 → 2700
            let t = (fractionalHour - 17.0) / 3.0
            return smoothInterpolate(from: 4500, to: 2700, t: t)
        } else {
            // Evening/night (20:00 - 6:00): 2700 → 2200 → 2700
            // Normalized so midnight is the lowest point
            let nightHour: Double
            if fractionalHour >= 20.0 {
                nightHour = fractionalHour - 20.0  // 0 to 4
            } else {
                nightHour = fractionalHour + 4.0   // 4 to 10
            }
            // Total night is 10 hours (20:00 to 6:00)
            let t = nightHour / 10.0
            // Dip to 2200 at midnight (t ≈ 0.4), come back to 2700 at edges
            let factor = sin(t * .pi)
            return 2700 - factor * 500  // 2700 → 2200 → 2700
        }
    }

    private init() {
        self.enabled = Self.sharedDefaults.bool(forKey: Self.enabledKey)
    }

    // MARK: - Start / Stop

    func start(apply: @escaping (Double) -> Void) {
        stop()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let temp = self.recommendedTemp
                apply(temp)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Helpers

    /// Smooth sinusoidal interpolation between two values. t in [0, 1].
    private func smoothInterpolate(from a: Double, to b: Double, t: Double) -> Double {
        let smoothT = (1.0 - cos(t * .pi)) / 2.0
        return a + (b - a) * smoothT
    }
}

// MARK: - MusicMoodManager

@MainActor
final class MusicMoodManager: ObservableObject {
    static let shared = MusicMoodManager()

    @Published var isActive: Bool = false
    @Published var detectedHue: Double = 0
    @Published var detectedSat: Double = 100

    private var pollingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Start / Stop

    func start(apply: @escaping (Double, Double) -> Void) {
        stop()
        isActive = true

        #if canImport(MediaPlayer)
        pollingTask = Task { [weak self] in
            let player = MPMusicPlayerController.systemMusicPlayer
            var lastItemId: MPMediaEntityPersistentID = 0

            while !Task.isCancelled {
                guard let self else { return }

                if let nowPlaying = player.nowPlayingItem {
                    let itemId = nowPlaying.persistentID
                    if itemId != lastItemId {
                        lastItemId = itemId
                        if let artwork = nowPlaying.artwork {
                            let size = CGSize(width: 1, height: 1)
                            if let image = artwork.image(at: size) {
                                let (hue, sat) = self.extractDominantColour(from: image)
                                self.detectedHue = hue
                                self.detectedSat = sat
                                apply(hue, sat)
                            }
                        }
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }
        }
        #endif
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isActive = false
    }

    // MARK: - Colour Extraction

    #if canImport(MediaPlayer)
    /// Scales the image down to 1×1 pixel and reads the colour, converting to HSB.
    #if canImport(UIKit)
    private func extractDominantColour(from image: UIImage) -> (hue: Double, sat: Double) {
        guard let cgImage = image.cgImage else { return (0, 100) }
        return extractHSB(from: cgImage)
    }
    #elseif canImport(AppKit)
    private func extractDominantColour(from image: NSImage) -> (hue: Double, sat: Double) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return (0, 100) }
        return extractHSB(from: cgImage)
    }
    #endif

    private func extractHSB(from cgImage: CGImage) -> (hue: Double, sat: Double) {
        let width = 1
        let height = 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return (0, 100) }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return (0, 100) }
        let pixel = data.assumingMemoryBound(to: UInt8.self)

        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0

        // Convert RGB to HSB
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC

        var hue: CGFloat = 0
        var saturation: CGFloat = 0

        if delta > 0 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                hue = (b - r) / delta + 2
            } else {
                hue = (r - g) / delta + 4
            }
            hue *= 60
            if hue < 0 { hue += 360 }
        }

        if maxC > 0 {
            saturation = delta / maxC
        }

        return (hue: Double(hue), sat: Double(saturation * 100))
    }
    #endif
}
