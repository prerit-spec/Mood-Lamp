import Foundation
import Network
import WidgetKit

enum WizError: LocalizedError {
    case noIP, timeout, badReply
    var errorDescription: String? {
        switch self {
        case .noIP: return "No lamp selected. Open the Mood Lamp app and enter the lamp's IP address."
        case .timeout: return "The lamp did not respond. Check that your device is on the same Wi-Fi and Local integrations is on in the WiZ app."
        case .badReply: return "The lamp sent a reply the app could not read."
        }
    }
}

/// Talks to a WiZ lamp directly over UDP (port 38899). No server needed.
final class WizClient: @unchecked Sendable {
    static let shared = WizClient()
    private static let appGroupIdentifier = "group.com.preritrudrakarpersonalteam.bulb"
    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    var ip: String {
        get {
            if let sharedIP = Self.sharedDefaults?.string(forKey: "bulbIp") {
                return sharedIP
            }
            let savedIP = UserDefaults.standard.string(forKey: "bulbIp") ?? ""
            if !savedIP.isEmpty {
                Self.sharedDefaults?.set(savedIP, forKey: "bulbIp")
            }
            return savedIP
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "bulbIp")
            Self.sharedDefaults?.set(newValue, forKey: "bulbIp")
        }
    }

    private final class Once: @unchecked Sendable {
        nonisolated(unsafe) var done = false
    }

    /// UDP has no delivery guarantee and Wi-Fi bulbs drop packets, so try a few times before giving up.
    func send(_ payload: [String: Any], to target: String? = nil, timeout: TimeInterval = 1.0, attempts: Int = 3) async throws -> [String: Any] {
        var lastError: Error = WizError.timeout
        for attempt in 0..<attempts {
            do { return try await sendOnce(payload, to: target, timeout: timeout) }
            catch WizError.noIP { throw WizError.noIP }
            catch {
                lastError = error
                if attempt < attempts - 1 { try? await Task.sleep(nanoseconds: 200_000_000) }
            }
        }
        throw lastError
    }

    private func sendOnce(_ payload: [String: Any], to target: String? = nil, timeout: TimeInterval) async throws -> [String: Any] {
        let host = (target ?? ip).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw WizError.noIP }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let conn = NWConnection(host: NWEndpoint.Host(host), port: 38899, using: .udp)
        let queue = DispatchQueue(label: "wiz.udp")
        let once = Once()

        return try await withCheckedThrowingContinuation { cont in
            func finish(_ result: Result<[String: Any], Error>) {
                guard !once.done else { return }
                once.done = true
                conn.cancel()
                cont.resume(with: result)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: data, completion: .contentProcessed { err in
                        if let err { finish(.failure(err)); return }
                        conn.receiveMessage { content, _, _, error in
                            if let error { finish(.failure(error)); return }
                            guard let content,
                                  let obj = try? JSONSerialization.jsonObject(with: content) as? [String: Any]
                            else { finish(.failure(WizError.badReply)); return }
                            finish(.success(obj))
                        }
                    })
                case .failed(let e): finish(.failure(e))
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(WizError.timeout)) }
            conn.start(queue: queue)
        }
    }

    func setPilot(_ params: [String: Any]) async throws {
        _ = try await sendResilient(["method": "setPilot", "params": params])
        if let state = params["state"] as? Bool {
            let defaults = Self.sharedDefaults
            let previousState = defaults?.object(forKey: "bulbOn") as? Bool
            defaults?.set(state, forKey: "bulbOn")
            if previousState != state { WidgetCenter.shared.reloadAllTimelines() }
        }
    }

    func getPilot(resilient: Bool = true) async throws -> [String: Any] {
        let payload: [String: Any] = ["method": "getPilot", "params": [String: Any]()]
        let reply: [String: Any]
        if resilient { reply = try await sendResilient(payload) }
        else { reply = try await send(payload, timeout: 1.0) }
        let result = reply["result"] as? [String: Any] ?? [:]
        if let m = result["mac"] as? String { mac = m }   // remembered so the lamp can be found again
        if let state = result["state"] as? Bool {
            let defaults = Self.sharedDefaults
            let previousState = defaults?.object(forKey: "bulbOn") as? Bool
            defaults?.set(state, forKey: "bulbOn")
            if previousState != state {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        if let dimming = result["dimming"] as? Int {
            Self.sharedDefaults?.set(dimming, forKey: "bulbDimming")
        }
        return result
    }

    // MARK: - Finding the lamp again after its IP changes

    /// The lamp's MAC address never changes, unlike its IP.
    var mac: String {
        get {
            Self.sharedDefaults?.string(forKey: "bulbMac")
                ?? UserDefaults.standard.string(forKey: "bulbMac")
                ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "bulbMac")
            Self.sharedDefaults?.set(newValue, forKey: "bulbMac")
        }
    }

    /// Sends to the saved IP. If the lamp stops answering, searches the network for its MAC and retries once.
    private func sendResilient(_ payload: [String: Any]) async throws -> [String: Any] {
        do {
            return try await send(payload)
        } catch WizError.timeout where !mac.isEmpty {
            guard let match = await scan().first(where: { $0.mac == mac }) else { throw WizError.timeout }
            ip = match.ip
            return try await send(payload)
        }
    }

    private func phoneSubnetPrefix() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  String(cString: ifa.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let parts = String(cString: host).split(separator: ".")
            if parts.count == 4 { return parts[0...2].joined(separator: ".") }
        }
        return nil
    }

    /// Asks every address on the home Wi-Fi (x.x.x.1 to .254) and returns the lamps that answer.
    func scan() async -> [(ip: String, mac: String)] {
        guard let prefix = phoneSubnetPrefix() else { return [] }
        var found: [(ip: String, mac: String)] = []
        for start in stride(from: 1, through: 254, by: 64) {
            await withTaskGroup(of: (String, String)?.self) { group in
                for n in start..<min(start + 64, 255) {
                    let target = "\(prefix).\(n)"
                    group.addTask {
                        guard let reply = try? await self.send(["method": "getPilot", "params": [String: Any]()], to: target, timeout: 0.6, attempts: 1),
                              let result = reply["result"] as? [String: Any],
                              let mac = result["mac"] as? String else { return nil }
                        return (target, mac)
                    }
                }
                for await item in group { if let item { found.append((ip: item.0, mac: item.1)) } }
            }
        }
        return found
    }
}
