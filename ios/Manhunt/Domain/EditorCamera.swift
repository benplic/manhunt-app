import Foundation
import MapKit

/// Default map framing for the arena editor.
enum EditorCamera {
    static let newYork = GeoPoint(latitude: 40.6616, longitude: -73.9688)

    static func region(user: GeoPoint?, boundary: [GeoPoint], isNew: Bool) -> MKCoordinateRegion {
        let span = MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)
        if isNew || boundary.count < 3 {
            let center = snapTarget(user: user)
            return MKCoordinateRegion(
                center: center.coordinate,
                span: span
            )
        }
        let visual = VisualArena(
            id: "edit",
            name: "",
            place: "",
            boundary: boundary.map { VisualPoint(latitude: $0.latitude, longitude: $0.longitude) },
            zones: []
        )
        return visual.region
    }

    static func snapTarget(user: GeoPoint?) -> GeoPoint {
        user ?? newYork
    }
}

private extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
