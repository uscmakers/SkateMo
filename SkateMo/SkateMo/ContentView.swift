import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var boardBLEManager: BoardBLEManager
    @StateObject private var rideSession: RideSessionManager

    init() {
        let boardBLEManager = BoardBLEManager()
        _boardBLEManager = StateObject(wrappedValue: boardBLEManager)
        _rideSession = StateObject(wrappedValue: RideSessionManager(boardBLEManager: boardBLEManager))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            MapPageView(
                rideSession: rideSession,
                locationManager: rideSession.locationManager,
                navigationManager: rideSession.navigationManager,
                bleManager: boardBLEManager
            )
                .tag(0)

            CameraView(
                rideSession: rideSession,
                locationManager: rideSession.locationManager,
                navigationManager: rideSession.navigationManager,
                cameraManager: rideSession.cameraManager,
                objectDetector: rideSession.objectDetector,
                obstacleEvaluator: rideSession.obstacleEvaluator
            )
                .tag(1)

            DebugPageView(
                rideSession: rideSession,
                navigationManager: rideSession.navigationManager,
                bleManager: boardBLEManager
            )
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            PersistentBLEStatusBadge(bleManager: boardBLEManager)
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .onAppear {
            rideSession.activateServicesIfNeeded()
        }
    }
}

struct MapPageView: View {
    @ObservedObject var rideSession: RideSessionManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var navigationManager: NavigationManager
    @ObservedObject var bleManager: BoardBLEManager

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0211, longitude: -118.2870),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )

    var body: some View {
        ZStack {
            // MAP LAYER
            MapReader { proxy in
                Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                    // Show user's current location as a blue dot
                    if let location = locationManager.location {
                        Annotation("", coordinate: location.coordinate) {
                            Circle()
                                .fill(.blue)
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: 3)
                                )
                                .shadow(radius: 3)
                        }
                    }

                    if let destinationCoordinate = rideSession.destinationCoordinate {
                        Marker("Destination",
                               systemImage: "mappin.and.ellipse",
                               coordinate: destinationCoordinate)
                    }

                    if rideSession.routeCoordinates.count >= 2 {
                        MapPolyline(MKPolyline(
                            coordinates: rideSession.routeCoordinates,
                            count: rideSession.routeCoordinates.count
                        ))
                        .stroke(.blue.opacity(0.9), lineWidth: 6)
                    }
                }
                .onTapGesture { location in
                    guard rideSession.rideStarted, rideSession.isSelectingDestination else { return }

                    if let coord = proxy.convert(location, from: .local) {
                        rideSession.setDestination(coord)
                    }
                }
            }

            // UI OVERLAY
            VStack {
                RideCommandBanner(
                    command: rideSession.bannerCommand,
                    title: rideSession.bannerTitle,
                    subtitle: rideSession.bannerSubtitle
                )
                .padding(.top, 50)
                .padding(.horizontal)

                // COORDINATES DISPLAY AT TOP
                if let location = locationManager.location {
                    VStack(spacing: 4) {
                        Text("Current Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(String(format: "%.8f, %.8f",
                                    location.coordinate.latitude,
                                    location.coordinate.longitude))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)
                } else {
                    Text("Acquiring location...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 8)
                }

                Text(rideSession.routeStatusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 8)

                BLEConnectionCard(bleManager: bleManager)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Swipe hint
                HStack {
                    Spacer()
                    Text("Swipe left for camera and debug")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                if !rideSession.rideStarted {
                    Button("Start Ride") {
                        rideSession.beginRideSetup()
                    }
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding()
                } else {
                    VStack(spacing: 8) {
                        Button(rideSession.destinationCoordinate == nil ? "Set Destination" : "Change Destination") {
                            rideSession.beginDestinationSelection()
                        }
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        if rideSession.destinationCoordinate != nil {
                            Button(rideSession.rideActive ? "Riding..." : "Start") {
                                rideSession.startRide()
                            }
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(rideSession.rideActive ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .disabled(rideSession.rideActive)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct DebugPageView: View {
    @ObservedObject var rideSession: RideSessionManager
    @ObservedObject var navigationManager: NavigationManager
    @ObservedObject var bleManager: BoardBLEManager

    @State private var forwardDurationSeconds = 1.5

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.11, blue: 0.14),
                    Color(red: 0.15, green: 0.18, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RideCommandBanner(
                        command: rideSession.bannerCommand,
                        title: "Board Debug",
                        subtitle: "Manual BLE tests and live turn-trigger tuning."
                    )
                    .padding(.top, 50)

                    BLEConnectionCard(bleManager: bleManager)

                    debugSection("Manual Commands") {
                        Text("Use these to exercise the skateboard link without rebuilding the app.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if !bleManager.isReadyToSend {
                            Text("Connect to the board before sending manual commands.")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }

                        if rideSession.rideActive {
                            Text("Ride automation is active, so later nav updates can overwrite a manual command.")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }

                        HStack(spacing: 12) {
                            Button("Left Position") {
                                bleManager.sendDebugCommand(.turnLeft)
                            }
                            .debugButtonStyle(background: Color.orange.opacity(0.9))
                            .disabled(!bleManager.isReadyToSend)

                            Button("Right Position") {
                                bleManager.sendDebugCommand(.turnRight)
                            }
                            .debugButtonStyle(background: Color.blue.opacity(0.9))
                            .disabled(!bleManager.isReadyToSend)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Forward burst")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: "%.1fs", forwardDurationSeconds))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Slider(
                                value: $forwardDurationSeconds,
                                in: 0.5...5.0,
                                step: 0.5
                            )

                            HStack(spacing: 12) {
                                Button("Send Forward") {
                                    bleManager.sendDebugForward(durationSeconds: forwardDurationSeconds)
                                }
                                .debugButtonStyle(background: Color.green.opacity(0.9))
                                .disabled(!bleManager.isReadyToSend)

                                Button("Stop") {
                                    bleManager.sendDebugStop()
                                }
                                .debugButtonStyle(background: Color.red.opacity(0.9))
                                .disabled(!bleManager.isReadyToSend)
                            }
                        }

                        Text(bleManager.manualDebugStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    debugSection("Turn Trigger Distance") {
                        Text("Adjust how far before an intersection the app issues the next turn command. Changes apply immediately and persist for the next launch.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Current trigger")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.0fm / %.0fft",
                                        navigationManager.turnTriggerDistanceMeters,
                                        navigationManager.turnTriggerDistanceMeters * 3.28084))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: Binding(
                                get: { navigationManager.turnTriggerDistanceMeters },
                                set: { navigationManager.updateTurnTriggerDistance($0) }
                            ),
                            in: NavigationManager.minimumTurnTriggerDistanceMeters...NavigationManager.maximumTurnTriggerDistanceMeters,
                            step: 1
                        )

                        Stepper(
                            value: Binding(
                                get: { navigationManager.turnTriggerDistanceMeters },
                                set: { navigationManager.updateTurnTriggerDistance($0) }
                            ),
                            in: NavigationManager.minimumTurnTriggerDistanceMeters...NavigationManager.maximumTurnTriggerDistanceMeters,
                            step: 1
                        ) {
                            Text("Fine tune in 1m steps")
                                .font(.caption.weight(.semibold))
                        }

                        Button("Reset to 15m Default") {
                            navigationManager.updateTurnTriggerDistance(
                                NavigationManager.defaultTurnTriggerDistanceMeters
                            )
                        }
                        .font(.caption.weight(.semibold))
                    }

                    debugSection("Quick Status") {
                        statusRow("Route", rideSession.routeStatusText)
                        statusRow("Effective command", rideSession.effectiveCommandText)
                        statusRow("Next instruction", rideSession.navigationManager.nextInstructionDisplayText.isEmpty ? "None" : rideSession.navigationManager.nextInstructionDisplayText)
                        statusRow("Distance to waypoint", navigationManager.distanceToNextWaypoint > 0 ? String(format: "%.1fm", navigationManager.distanceToNextWaypoint) : "--")
                    }

                    Text("Swipe right for camera and map")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func debugSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

struct BLEConnectionCard: View {
    @ObservedObject var bleManager: BoardBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Board BLE", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(statusColor)
            }

            Text("Drops: \(bleManager.disconnectCount)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Last sent: \(bleManager.lastSentCommand?.displayText ?? "None")")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("Last ACK: \(bleManager.lastAckedCommand?.displayText ?? "None")")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(bleManager.lastPeripheralMessage)
                .font(.caption2)
                .foregroundColor(.secondary)

            if let lastError = bleManager.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Button("Retry BLE Connection") {
                bleManager.retryConnection()
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusText: String {
        if bleManager.connectionState == .connected {
            return "Connected"
        }

        if bleManager.hasDroppedConnection {
            switch bleManager.connectionState {
            case .connecting:
                return "Dropped - Reconnecting"
            case .scanning:
                return "Dropped - Scanning"
            default:
                return "Dropped"
            }
        }

        return bleManager.connectionState.displayText
    }

    private var statusColor: Color {
        switch bleManager.connectionState {
        case .connected:
            return .green
        case .connecting, .scanning:
            return bleManager.hasDroppedConnection ? .red : .orange
        case .bluetoothUnavailable, .unauthorized, .failed:
            return .red
        case .idle:
            return .secondary
        }
    }
}

struct PersistentBLEStatusBadge: View {
    @ObservedObject var bleManager: BoardBLEManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(headline)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
            }

            Text(detail)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var headline: String {
        if bleManager.connectionState == .connected {
            return "BLE Connected"
        }

        if bleManager.hasDroppedConnection {
            switch bleManager.connectionState {
            case .connecting:
                return "BLE Reconnecting"
            case .scanning:
                return "BLE Dropped"
            default:
                return "BLE Lost"
            }
        }

        switch bleManager.connectionState {
        case .idle:
            return "BLE Idle"
        case .scanning:
            return "BLE Scanning"
        case .connecting:
            return "BLE Connecting"
        case .connected:
            return "BLE Connected"
        case .bluetoothUnavailable:
            return "Bluetooth Off"
        case .unauthorized:
            return "Bluetooth Denied"
        case .failed:
            return "BLE Failed"
        }
    }

    private var detail: String {
        if bleManager.connectionState == .connected {
            return "Board link ready"
        }

        if bleManager.hasDroppedConnection {
            return "Last link dropped"
        }

        return bleManager.lastPeripheralMessage
    }

    private var statusColor: Color {
        switch bleManager.connectionState {
        case .connected:
            return .green
        case .connecting, .scanning:
            return bleManager.hasDroppedConnection ? .red : .orange
        case .bluetoothUnavailable, .unauthorized, .failed:
            return .red
        case .idle:
            return .secondary
        }
    }
}

private extension View {
    func debugButtonStyle(background: Color) -> some View {
        self
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(background)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    ContentView()
}
