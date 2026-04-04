//
//  LocationManager.swift
//  SkateMo
//
//  Created by Justin Jiang on 1/29/26.
//
import CoreLocation
import SwiftUI

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published private(set) var courseDegrees: Double?
    @Published private(set) var compassHeadingDegrees: Double?
    @Published private(set) var travelHeadingDegrees: Double?

    // Callback for location updates - used by NavigationManager
    var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone  // Report all movements
        manager.activityType = .otherNavigation
        manager.headingFilter = 5
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
        startUpdatingHeading()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        stopUpdatingHeading()
    }

    func startUpdatingHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        guard CLLocationManager.headingAvailable() else { return }
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else { return }
        location = newLocation
        updateCourseHeading(from: newLocation)
        onLocationUpdate?(newLocation)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if heading >= 0 {
            compassHeadingDegrees = Self.normalizedHeading(heading)
        } else {
            compassHeadingDegrees = nil
        }

        updatePreferredHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    private func updateCourseHeading(from location: CLLocation) {
        if location.speed >= 0.8, location.course >= 0 {
            courseDegrees = Self.normalizedHeading(location.course)
        } else {
            courseDegrees = nil
        }

        updatePreferredHeading()
    }

    private func updatePreferredHeading() {
        travelHeadingDegrees = courseDegrees ?? compassHeadingDegrees
    }

    private static func normalizedHeading(_ value: CLLocationDirection) -> Double {
        var normalized = value.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }
}
