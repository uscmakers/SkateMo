import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
    }
    
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first
        if let loc = locations.first {
            print("Lat: \(loc.coordinate.latitude), Lon: \(loc.coordinate.longitude)")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Location Tracker")
                .font(.title)
            
            if let location = locationManager.location {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Latitude: \(location.coordinate.latitude)")
                    Text("Longitude: \(location.coordinate.longitude)")
                    Text("Altitude: \(location.altitude) m")
                    Text("Speed: \(location.speed) m/s")
                    Text("Accuracy: \(location.horizontalAccuracy) m")
                }
                .padding()
            } else {
                Text("Waiting for location...")
                    .foregroundColor(.gray)
            }
            
            Button("Start Tracking") {
                locationManager.requestPermission()
                locationManager.startUpdating()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

