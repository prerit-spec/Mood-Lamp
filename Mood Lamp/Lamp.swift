import Combine
import Foundation
import SwiftUI
import WidgetKit

// MARK: - SavedLamp Model

struct SavedLamp: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var ip: String
    var mac: String

    init(id: UUID = UUID(), name: String = "Mood Lamp", ip: String, mac: String = "") {
        self.id = id
        self.name = name
        self.ip = ip
        self.mac = mac
    }
}

// MARK: - SavedColour Model

struct SavedColour: Identifiable, Codable, Hashable {
    let id: UUID
    var hue: Double   // 0...360
    var sat: Double    // 0...100

    init(id: UUID = UUID(), hue: Double, sat: Double) {
        self.id = id
        self.hue = hue
        self.sat = sat
    }
}

// MARK: - LampStore

@MainActor
final class LampStore: ObservableObject {
    static let shared = LampStore()

    private static let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"
    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
    }

    private let defaults: UserDefaults

    // MARK: - Published State

    @Published var lamps: [SavedLamp] {
        didSet { saveLamps() }
    }

    @Published var activeLampId: UUID? {
        didSet { saveActiveLampId() }
    }

    @Published var savedColours: [SavedColour] {
        didSet { saveColours() }
    }

    @Published var favouriteSceneRawValues: Set<String> {
        didSet { saveFavourites() }
    }

    // MARK: - Computed Properties

    var activeLamp: SavedLamp? {
        lamps.first(where: { $0.id == activeLampId })
    }

    var sortedScenes: [MoodLampScene] {
        let favourites = MoodLampScene.allCases.filter { favouriteSceneRawValues.contains($0.rawValue) }
        let rest = MoodLampScene.allCases.filter { !favouriteSceneRawValues.contains($0.rawValue) }
        return favourites + rest
    }

    // MARK: - Init

    private init() {
        let defaults = Self.sharedDefaults
        self.defaults = defaults

        // Load lamps
        if let data = defaults.data(forKey: "savedLamps"),
           let decoded = try? JSONDecoder().decode([SavedLamp].self, from: data) {
            self.lamps = decoded
        } else {
            self.lamps = []
        }

        // Load active lamp ID
        if let idString = defaults.string(forKey: "activeLampId"),
           let id = UUID(uuidString: idString) {
            self.activeLampId = id
        } else {
            self.activeLampId = nil
        }

        // Load saved colours
        if let data = defaults.data(forKey: "savedColours"),
           let decoded = try? JSONDecoder().decode([SavedColour].self, from: data) {
            self.savedColours = decoded
        } else {
            self.savedColours = []
        }

        // Load favourite scenes
        if let data = defaults.data(forKey: "favouriteSceneRawValues"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.favouriteSceneRawValues = decoded
        } else {
            self.favouriteSceneRawValues = []
        }

        // Migration: if no saved lamps but legacy "bulbIp" key exists, auto-create one
        if lamps.isEmpty {
            let legacyIP = defaults.string(forKey: "bulbIp")
                ?? UserDefaults.standard.string(forKey: "bulbIp")
                ?? ""
            if !legacyIP.isEmpty {
                let legacyMac = defaults.string(forKey: "bulbMac")
                    ?? UserDefaults.standard.string(forKey: "bulbMac")
                    ?? ""
                let lamp = SavedLamp(name: "Mood Lamp", ip: legacyIP, mac: legacyMac)
                self.lamps = [lamp]
                self.activeLampId = lamp.id
                syncActiveToWizClient(lamp)
            }
        } else if let activeId = activeLampId, let lamp = lamps.first(where: { $0.id == activeId }) {
            syncActiveToWizClient(lamp)
        }
    }

    // MARK: - Lamp CRUD

    func add(_ lamp: SavedLamp) {
        lamps.append(lamp)
        if activeLampId == nil {
            setActive(lamp.id)
        }
    }

    func remove(id: UUID) {
        lamps.removeAll(where: { $0.id == id })
        if activeLampId == id {
            let newActiveId = lamps.first?.id
            activeLampId = newActiveId
            if let newActiveId, let lamp = lamps.first(where: { $0.id == newActiveId }) {
                syncActiveToWizClient(lamp)
            } else {
                WizClient.shared.ip = ""
                WizClient.shared.mac = ""
            }
        }
    }

    func update(_ lamp: SavedLamp) {
        if let index = lamps.firstIndex(where: { $0.id == lamp.id }) {
            lamps[index] = lamp
            if activeLampId == lamp.id {
                syncActiveToWizClient(lamp)
            }
        }
    }

    func setActive(_ id: UUID) {
        activeLampId = id
        if let lamp = lamps.first(where: { $0.id == id }) {
            syncActiveToWizClient(lamp)
        }
    }

    // MARK: - Saved Colours

    func saveColour(hue: Double, sat: Double) {
        let colour = SavedColour(hue: hue, sat: sat)
        savedColours.insert(colour, at: 0)
        if savedColours.count > 12 {
            savedColours = Array(savedColours.prefix(12))
        }
    }

    func removeColour(id: UUID) {
        savedColours.removeAll(where: { $0.id == id })
    }

    // MARK: - Favourite Scenes

    func toggleFavourite(_ scene: MoodLampScene) {
        if favouriteSceneRawValues.contains(scene.rawValue) {
            favouriteSceneRawValues.remove(scene.rawValue)
        } else {
            favouriteSceneRawValues.insert(scene.rawValue)
        }
    }

    func isFavourite(_ scene: MoodLampScene) -> Bool {
        favouriteSceneRawValues.contains(scene.rawValue)
    }

    // MARK: - Private Helpers

    private func syncActiveToWizClient(_ lamp: SavedLamp) {
        WizClient.shared.ip = lamp.ip
        WizClient.shared.mac = lamp.mac
        // Also ensure "bulbIp" is set in shared defaults for widget
        Self.sharedDefaults.set(lamp.ip, forKey: "bulbIp")
    }

    private func saveLamps() {
        guard let data = try? JSONEncoder().encode(lamps) else { return }
        defaults.set(data, forKey: "savedLamps")
    }

    private func saveActiveLampId() {
        defaults.set(activeLampId?.uuidString, forKey: "activeLampId")
    }

    private func saveColours() {
        guard let data = try? JSONEncoder().encode(savedColours) else { return }
        defaults.set(data, forKey: "savedColours")
    }

    private func saveFavourites() {
        guard let data = try? JSONEncoder().encode(favouriteSceneRawValues) else { return }
        defaults.set(data, forKey: "favouriteSceneRawValues")
        syncFavouriteScenesToWidget()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Syncs the first 4 favourite scenes to shared defaults as JSON for the widget.
    /// Format: [{"id": sceneId, "title": label}]
    private func syncFavouriteScenesToWidget() {
        let favouriteScenes = MoodLampScene.allCases.filter { favouriteSceneRawValues.contains($0.rawValue) }
        let topFour = Array(favouriteScenes.prefix(4))
        let widgetPayload: [[String: Any]] = topFour.map { scene in
            ["id": scene.sceneId, "title": scene.label]
        }
        if let data = try? JSONSerialization.data(withJSONObject: widgetPayload) {
            Self.sharedDefaults.set(data, forKey: "favouriteWidgetScenes")
        }
    }
}
