//
//  BoardBLEManager.swift
//  SkateMo
//

import CoreBluetooth
import Foundation

enum BLEConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case bluetoothUnavailable
    case unauthorized
    case failed

    var displayText: String {
        switch self {
        case .idle:
            return "Idle"
        case .scanning:
            return "Scanning"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .bluetoothUnavailable:
            return "Bluetooth Off"
        case .unauthorized:
            return "Bluetooth Denied"
        case .failed:
            return "Connection Failed"
        }
    }
}

final class BoardBLEManager: NSObject, ObservableObject {
    enum NotificationPayload: Equatable {
        case ack(BoardBLECommand)
        case message(String)
        case unknown(String)
    }

    static let targetPeripheralName = "ESP32_Motor_Controller"
    static let serviceUUID = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
    static let characteristicUUID = CBUUID(string: "BEB5483E-36E1-4688-B7F5-EA07361B26A8")

    @Published private(set) var connectionState: BLEConnectionState = .idle
    @Published private(set) var isReadyToSend = false
    @Published private(set) var lastSentCommand: BoardBLECommand?
    @Published private(set) var lastAckedCommand: BoardBLECommand?
    @Published private(set) var lastPeripheralMessage = "Waiting for board connection."
    @Published private(set) var lastError: String?
    @Published private(set) var hasEverConnected = false
    @Published private(set) var hasDroppedConnection = false
    @Published private(set) var disconnectCount = 0
    @Published private(set) var manualDebugStatus = "Manual controls idle."

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var latestDesiredCommand: BoardBLECommand?
    private var lastTransmittedCommand: BoardBLECommand?
    private var hasActivated = false
    private let testWriter: ((Data) -> Void)?
    private var scheduledDebugStopWorkItem: DispatchWorkItem?

    init(testWriter: ((Data) -> Void)? = nil) {
        self.testWriter = testWriter
        super.init()

        if testWriter != nil {
            connectionState = .connected
            isReadyToSend = true
            lastPeripheralMessage = "Using test BLE transport."
            hasEverConnected = true
        }
    }

    func activate() {
        guard testWriter == nil else { return }

        if let centralManager {
            if centralManager.state == .poweredOn {
                startScanning()
            }
            return
        }

        hasActivated = true
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func retryConnection() {
        lastError = nil
        lastPeripheralMessage = "Retrying BLE connection..."

        guard testWriter == nil else {
            simulateReadyForTesting()
            return
        }

        resetActiveConnection()
        activate()
    }

    func send(command: BoardBLECommand) {
        latestDesiredCommand = command

        guard isReadyToSend else { return }
        flushLatestCommand(force: false)
    }

    func sendDebugCommand(_ command: BoardBLECommand) {
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil
        manualDebugStatus = "Sent \(command.displayText)."
        send(command: command)
    }

    func sendDebugForward(durationSeconds: TimeInterval) {
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil

        let durationSeconds = max(0.5, durationSeconds)
        manualDebugStatus = String(format: "Forward for %.1fs, then stop.", durationSeconds)
        send(command: .forward)

        let stopWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.send(command: .stop)
            self.manualDebugStatus = String(format: "Forward burst complete after %.1fs.", durationSeconds)
            self.scheduledDebugStopWorkItem = nil
        }

        scheduledDebugStopWorkItem = stopWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds, execute: stopWorkItem)
    }

    func sendDebugStop() {
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil
        manualDebugStatus = "Sent STOP."
        send(command: .stop)
    }

    func simulateDisconnectForTesting() {
        guard testWriter != nil else { return }
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil
        isReadyToSend = false
        connectionState = .scanning
        hasDroppedConnection = true
        disconnectCount += 1
        lastPeripheralMessage = "Simulated BLE disconnect."
    }

    func simulateReadyForTesting() {
        guard testWriter != nil else { return }
        isReadyToSend = true
        connectionState = .connected
        hasEverConnected = true
        hasDroppedConnection = false
        lastPeripheralMessage = "Simulated BLE reconnect."
        lastTransmittedCommand = nil
        flushLatestCommand(force: true)
    }

    static func parseNotification(_ data: Data) -> NotificationPayload {
        guard !data.isEmpty else {
            return .unknown("Empty payload")
        }

        if let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)),
           !message.isEmpty {
            if let ackedCommand = BoardBLECommand(notificationString: message) {
                return .ack(ackedCommand)
            }
            return .message(message)
        }

        let hexString = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        return .unknown(hexString)
    }

    private func startScanning() {
        guard let centralManager else { return }

        switch centralManager.state {
        case .poweredOn:
            if peripheral == nil {
                connectionState = .scanning
                lastPeripheralMessage = "Scanning for \(Self.targetPeripheralName)..."
                centralManager.scanForPeripherals(
                    withServices: [Self.serviceUUID],
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        case .unauthorized:
            connectionState = .unauthorized
            isReadyToSend = false
            lastError = "Bluetooth permission denied."
        default:
            connectionState = .bluetoothUnavailable
            isReadyToSend = false
        }
    }

    private func resetActiveConnection() {
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil
        if let peripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        commandCharacteristic = nil
        isReadyToSend = false
        lastTransmittedCommand = nil
    }

    private func flushLatestCommand(force: Bool) {
        guard let latestDesiredCommand, isReadyToSend else { return }
        if !force, lastTransmittedCommand == latestDesiredCommand { return }

        guard let data = latestDesiredCommand.transportString.data(using: .utf8) else {
            lastError = "Failed to encode BLE command."
            lastPeripheralMessage = "Command encoding failed."
            return
        }

        if let testWriter {
            testWriter(data)
        } else if let peripheral, let commandCharacteristic {
            peripheral.writeValue(data, for: commandCharacteristic, type: .withResponse)
        } else {
            return
        }

        lastSentCommand = latestDesiredCommand
        lastTransmittedCommand = latestDesiredCommand
        lastPeripheralMessage = "Sent \(latestDesiredCommand.displayText)"
    }

    private func handleCentralState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if hasActivated {
                startScanning()
            }
        case .unauthorized:
            connectionState = .unauthorized
            isReadyToSend = false
            lastError = "Bluetooth permission denied."
        case .poweredOff, .unsupported, .resetting:
            connectionState = .bluetoothUnavailable
            isReadyToSend = false
            lastPeripheralMessage = "Bluetooth is unavailable."
        case .unknown:
            connectionState = .idle
            isReadyToSend = false
        @unknown default:
            connectionState = .failed
            isReadyToSend = false
            lastError = "Unknown Bluetooth state."
        }
    }

    private func matchesTarget(_ discoveredPeripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if advertisedName == Self.targetPeripheralName || discoveredPeripheral.name == Self.targetPeripheralName {
            return true
        }

        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]
        return advertisedServices?.contains(Self.serviceUUID) == true
    }

    private func markLinkReady(message: String) {
        connectionState = .connected
        isReadyToSend = true
        hasEverConnected = true
        hasDroppedConnection = false
        lastError = nil
        lastPeripheralMessage = message
        lastTransmittedCommand = nil
        flushLatestCommand(force: true)
    }
}

extension BoardBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        handleCentralState(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard matchesTarget(peripheral, advertisementData: advertisementData) else { return }

        self.peripheral = peripheral
        commandCharacteristic = nil
        isReadyToSend = false
        lastTransmittedCommand = nil
        let discoveredName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? Self.targetPeripheralName
        lastPeripheralMessage = "Discovered \(discoveredName). Connecting..."
        connectionState = .connecting

        central.stopScan()
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connecting
        lastPeripheralMessage = "Connected. Discovering BLE services..."
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed
        isReadyToSend = false
        lastError = error?.localizedDescription ?? "Failed to connect to board."
        lastPeripheralMessage = "BLE connection failed. Retrying..."
        self.peripheral = nil
        startScanning()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        scheduledDebugStopWorkItem?.cancel()
        scheduledDebugStopWorkItem = nil
        self.peripheral = nil
        commandCharacteristic = nil
        isReadyToSend = false
        lastTransmittedCommand = nil
        hasDroppedConnection = true
        disconnectCount += 1
        lastError = error?.localizedDescription
        lastPeripheralMessage = "Board disconnected. Reconnecting..."
        connectionState = .scanning
        startScanning()
    }
}

extension BoardBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .failed
            lastError = error.localizedDescription
            lastPeripheralMessage = "Service discovery failed."
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            connectionState = .failed
            lastError = "Expected BLE service not found."
            lastPeripheralMessage = "Missing command service."
            return
        }

        lastPeripheralMessage = "Service found. Discovering command characteristic..."
        peripheral.discoverCharacteristics([Self.characteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionState = .failed
            lastError = error.localizedDescription
            lastPeripheralMessage = "Characteristic discovery failed."
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.characteristicUUID }) else {
            connectionState = .failed
            lastError = "Expected BLE characteristic not found."
            lastPeripheralMessage = "Missing command characteristic."
            return
        }

        commandCharacteristic = characteristic

        if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
            peripheral.setNotifyValue(true, for: characteristic)
        } else if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
            markLinkReady(message: "BLE link ready. Notifications unavailable on board.")
        } else {
            connectionState = .failed
            isReadyToSend = false
            lastError = "Characteristic is not writable."
            lastPeripheralMessage = "Board characteristic cannot accept commands."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            connectionState = .failed
            isReadyToSend = false
            lastError = error.localizedDescription
            lastPeripheralMessage = "Could not subscribe to board notifications."
            return
        }

        guard characteristic.uuid == Self.characteristicUUID else { return }

        markLinkReady(message: "BLE link ready.")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.characteristicUUID else { return }

        if let error {
            lastError = error.localizedDescription
            lastPeripheralMessage = "Write failed."
        } else if commandCharacteristic?.properties.contains(.notify) != true &&
                    commandCharacteristic?.properties.contains(.indicate) != true {
            lastPeripheralMessage = "Command delivered without board notifications."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.characteristicUUID else { return }

        if let error {
            lastError = error.localizedDescription
            lastPeripheralMessage = "Notification read failed."
            return
        }

        guard let value = characteristic.value else { return }

        switch Self.parseNotification(value) {
        case let .ack(command):
            lastAckedCommand = command
            lastPeripheralMessage = "ACK \(command.displayText)"
        case let .message(message):
            lastPeripheralMessage = message
        case let .unknown(payload):
            lastPeripheralMessage = "Unknown payload: \(payload)"
        }
    }
}
