import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var rideSession = RideSessionManager()

    var body: some View {
        TabView(selection: $selectedTab) {
            MapPageView(
                rideSession: rideSession,
                locationManager: rideSession.locationManager,
                navigationManager: rideSession.navigationManager
            )
                .tag(0)

            CameraView(
                rideSession: rideSession,
                cameraManager: rideSession.cameraManager,
                objectDetector: rideSession.objectDetector,
                obstacleEvaluator: rideSession.obstacleEvaluator
            )
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .ignoresSafeArea()
        .onAppear {
            rideSession.activateServicesIfNeeded()
        }
    }
}

struct MapPageView: View {
    @ObservedObject var rideSession: RideSessionManager
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var navigationManager: NavigationManager

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

#Preview {
    ContentView()
}
