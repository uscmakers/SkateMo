import SwiftUI
import MapKit
import CoreLocation

struct Pin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapPageView()
                .tag(0)

            CameraView()
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .ignoresSafeArea()
    }
}

struct MapPageView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var navigationManager = NavigationManager()

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.0211, longitude: -118.2870),
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )

    @State private var rideStarted = false
    @State private var isSelectingDestination = false
    @State private var destinationPin: Pin? = nil
    @State private var rideActive = false

    var body: some View {
        ZStack {
            // MAP LAYER
            MapReader { proxy in
                Map(position: $cameraPosition, interactionModes: []) {
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

                    if let destinationPin {
                        Marker("Destination",
                               systemImage: "mappin.and.ellipse",
                               coordinate: destinationPin.coordinate)
                    }
                }
                .onTapGesture { location in
                    guard rideStarted, isSelectingDestination else { return }

                    if let coord = proxy.convert(location, from: .local) {
                        destinationPin = Pin(coordinate: coord)
                        isSelectingDestination = false
                    }
                }
            }

            // UI OVERLAY
            VStack {
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
                    .padding(.top, 50)
                } else {
                    Text("Acquiring location...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 50)
                }

                // Swipe hint
                HStack {
                    Spacer()
                    Text("Swipe left for camera")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Spacer()

                if !rideStarted {
                    Button("Start Ride") {
                        rideStarted = true
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
                        Button(destinationPin == nil ? "Set Destination" : "Change Destination") {
                            isSelectingDestination = true
                        }
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                        if destinationPin != nil {
                            Button(rideActive ? "Riding..." : "Start") {
                                rideActive = true
                                print("Ride started with destination: \(String(describing: destinationPin?.coordinate))")
                                startNavigationWithSampleRoute()
                            }
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(rideActive ? Color.gray : Color.orange)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .disabled(rideActive)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()

            // Wire up location updates to navigation manager
            locationManager.onLocationUpdate = { location in
                navigationManager.updateLocation(location)
            }
        }
    }

    // Start navigation with sample waypoints for testing
    // In production, these would come from path calculation
    private func startNavigationWithSampleRoute() {
        let sampleWaypoints: [Waypoint] = [
            Waypoint(
                name: "Start Point",
                coordinate: CLLocationCoordinate2D(latitude: 34.0211, longitude: -118.2870),
                instruction: "Start"
            ),
            Waypoint(
                name: "West 34th & Watt Way",
                coordinate: CLLocationCoordinate2D(latitude: 34.0195, longitude: -118.2879),
                instruction: "Right"
            ),
            Waypoint(
                name: "Destination",
                coordinate: destinationPin?.coordinate ?? CLLocationCoordinate2D(latitude: 34.0185, longitude: -118.2879),
                instruction: "Destination"
            )
        ]

        navigationManager.startNavigation(with: sampleWaypoints)
    }
}

#Preview {
    ContentView()
}
