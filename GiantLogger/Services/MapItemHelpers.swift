import CoreLocation
import MapKit

extension MKMapItem {
    convenience init(coordinate: CLLocationCoordinate2D) {
        self.init(
            location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
            address: nil
        )
    }
}
