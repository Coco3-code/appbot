import CoreBluetooth

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let charUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let statusUUID = CBUUID(string: "6E400004-B5A3-F393-E0A9-E50E24DCCA9E")

    /// Derniere commande manuelle (code ASCII : F, B, L, R, X) notifiee par l'ESP32
    private(set) var lastCmd: UInt8 = 88

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    @Published var status = "Recherche de l'ESP32..."

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    private func scan() {
        central.scanForPeripherals(withServices: [Self.serviceUUID])
        status = "Recherche de l'ESP32..."
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        if c.state == .poweredOn { scan() } else { status = "Bluetooth indisponible" }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peripheral = p
        p.delegate = self
        c.stopScan()
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "Connecte"
        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        characteristic = nil
        scan()
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics([Self.charUUID, Self.statusUUID], for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            if c.uuid == Self.charUUID { characteristic = c }
            if c.uuid == Self.statusUUID { p.setNotifyValue(true, for: c) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard c.uuid == Self.statusUUID, let d = c.value, d.count >= 2 else { return }
        lastCmd = d[1]
    }

    func send(_ data: Data) {
        guard let p = peripheral, let c = characteristic, p.canSendWriteWithoutResponse else { return }
        p.writeValue(data, for: c, type: .withoutResponse)
    }

    /// Pour les messages critiques (STOP, GO) : avec accuse de reception.
    func sendReliable(_ data: Data) {
        guard let p = peripheral, let c = characteristic else { return }
        p.writeValue(data, for: c, type: .withResponse)
    }
}
