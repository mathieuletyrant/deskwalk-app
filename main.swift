import AppKit
import CoreBluetooth
import ServiceManagement

// WalkingPad A1/R1/C2/P1 protocol (service FE00, notify FE01, write FE02), as reverse-engineered by ph4-walkingpad.
func cmd(_ k: UInt8, _ v: UInt8) -> [UInt8] { [0xF7, 0xA2, k, v, UInt8((0xA2 + Int(k) + Int(v)) & 0xFF), 0xFD] }
func int3(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 16 | Int(b[i + 1]) << 8 | Int(b[i + 2]) }

struct Stats { var belt = 0, speed = 0.0, time = 0, distKm = 0.0, steps = 0 }

func parse(_ m: [UInt8]) -> Stats? {
    guard m.count >= 14, m[0] == 0xF8, m[1] == 0xA2 else { return nil }
    return Stats(belt: Int(m[2]), speed: Double(m[3]) / 10, time: int3(m, 5), distKm: Double(int3(m, 8)) / 100, steps: int3(m, 11))
}

enum Session {
    // iCloud Drive/Shortcuts/Deskwalk: the folder the Shortcuts app reads without extra permission.
    static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents/Deskwalk")

    static func save(_ s: Stats) {
        guard s.time >= 60 else { return }
        let end = Date(), start = end.addingTimeInterval(-Double(s.time))
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        let json: [String: Any] = [
            "start": f.string(from: start), "end": f.string(from: end),
            "durationMin": s.time / 60, "distanceKm": s.distKm, "steps": s.steps,
        ]
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: json)
                .write(to: dir.appendingPathComponent("\(Int(end.timeIntervalSince1970)).json"))
        } catch {
            NSLog("Deskwalk: session not saved: \(error) \(json)")
        }
    }
}

final class Pad: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var queue: [[UInt8]] = []
    private var lastRun: Stats?
    var stats = Stats()
    var connected: Bool { writer != nil }
    var onChange: () -> Void = {}

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        // ponytail: one 0.7 s tick paces commands (the pad drops faster ones) and polls stats when idle.
        Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in self?.tick() }
    }

    // manual mode, start belt, wait out the ~3 s countdown (stat polls), then the default speed
    func go(_ kmh: Double) {
        queue += [cmd(2, 1), cmd(4, 1)] + Array(repeating: cmd(0, 0), count: 6)
        setSpeed(kmh)
    }
    func stop() { queue.append(cmd(1, 0)) }
    func setSpeed(_ kmh: Double) { queue.append(cmd(1, UInt8(min(60, max(0, kmh * 10)).rounded()))) }

    private func tick() {
        guard let p = peripheral, let w = writer else { return }
        let bytes = queue.isEmpty ? cmd(0, 0) : queue.removeFirst()
        p.writeValue(Data(bytes), for: w, type: w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
    }

    private func rescan() {
        writer = nil
        peripheral = nil
        onChange()
        if central.state == .poweredOn { central.scanForPeripherals(withServices: nil) }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { c.scanForPeripherals(withServices: nil) }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData ad: [String: Any], rssi: NSNumber) {
        let name = (p.name ?? ad[CBAdvertisementDataLocalNameKey] as? String ?? "").lowercased()
        guard name.contains("walkingpad") || name.hasPrefix("ks-") else { return }
        c.stopScan()
        peripheral = p
        p.delegate = self
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([CBUUID(string: "FE00")]) }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) { rescan() }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) { rescan() }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        p.services?.forEach { p.discoverCharacteristics([CBUUID(string: "FE01"), CBUUID(string: "FE02")], for: $0) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == CBUUID(string: "FE01") { p.setNotifyValue(true, for: ch) }
            if ch.uuid == CBUUID(string: "FE02") { writer = ch }
        }
        onChange()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, let s = parse([UInt8](d)) else { return }
        if s.belt == 1 {
            lastRun = s
        } else if let run = lastRun {
            lastRun = nil
            Session.save(run)
        }
        stats = s
        onChange()
    }
}

final class App: NSObject, NSApplicationDelegate {
    let pad = Pad()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let info = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    let speeds = NSMenu()
    lazy var login: NSMenuItem = {
        let i = NSMenuItem(title: "Lancer au démarrage", action: #selector(toggleLogin), keyEquivalent: "")
        i.target = self
        return i
    }()
    var defaultSpeed: Double {
        get { UserDefaults.standard.object(forKey: "defaultSpeed") as? Double ?? 3.0 }
        set { UserDefaults.standard.set(newValue, forKey: "defaultSpeed") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let menu = NSMenu()
        menu.addItem(info)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Go", action: #selector(go), keyEquivalent: "g").target = self
        menu.addItem(withTitle: "Stop", action: #selector(stop), keyEquivalent: "s").target = self
        for kmh in stride(from: 1.0, through: 6.0, by: 0.5) {
            let i = speeds.addItem(withTitle: "\(kmh) km/h", action: #selector(speed(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = kmh
        }
        menu.addItem(withTitle: "Vitesse", action: nil, keyEquivalent: "").submenu = speeds
        menu.addItem(.separator())
        menu.addItem(login)
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        item.button?.image = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Deskwalk")
        item.button?.imagePosition = .imageLeading
        pad.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        let s = pad.stats
        item.button?.appearsDisabled = !pad.connected
        item.button?.title = s.belt == 1 && pad.connected ? String(format: " %d pas · %d:%02d", s.steps, s.time / 60, s.time % 60) : ""
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        speeds.items.forEach { $0.state = $0.representedObject as? Double == defaultSpeed ? .on : .off }
        info.title = pad.connected ? String(format: "%d min · %.2f km · %d pas", s.time / 60, s.distKm, s.steps) : "Recherche du tapis…"
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Deskwalk: login item: \(error)")
        }
        refresh()
    }

    @objc func go() { pad.go(defaultSpeed) }
    @objc func stop() { pad.stop() }
    // Picking a speed applies it now and keeps it as the speed Go starts at.
    @objc func speed(_ i: NSMenuItem) {
        defaultSpeed = i.representedObject as! Double
        pad.setSpeed(defaultSpeed)
        refresh()
    }

    // deskwalk://go, deskwalk://stop, deskwalk://speed/3.5
    func application(_ app: NSApplication, open urls: [URL]) {
        for u in urls {
            switch u.host {
            case "go": pad.go(defaultSpeed)
            case "stop": pad.stop()
            case "speed": if let v = Double(u.lastPathComponent) { pad.setSpeed(v) }
            default: NSLog("Deskwalk: unknown URL \(u)")
            }
        }
    }
}

if CommandLine.arguments.contains("--selftest") {
    precondition(cmd(0, 0) == [0xF7, 0xA2, 0, 0, 0xA2, 0xFD])
    precondition(cmd(4, 1) == [0xF7, 0xA2, 4, 1, 0xA7, 0xFD])
    let s = parse([0xF8, 0xA2, 1, 35, 1, 0, 1, 44, 0, 0, 123, 0, 4, 210, 0])!
    precondition(s.belt == 1 && s.speed == 3.5 && s.time == 300 && s.distKm == 1.23 && s.steps == 1234)
    print("selftest ok")
    exit(0)
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
