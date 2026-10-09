import CoreLocation
@testable import GiantLogger
import Testing

struct RouteProgressTests {
    private static let origin = CLLocationCoordinate2D(latitude: 55.1, longitude: 14.9)
    private static let threshold: CLLocationDistance = 50

    /// A coordinate `east` and `north` metres from the test origin.
    private static func point(_ east: Double, _ north: Double) -> CLLocationCoordinate2D {
        let latitude = origin.latitude + north / 111_320
        let longitude = origin.longitude + east / (111_320 * cos(origin.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func line(_ points: [(Double, Double)]) -> [CLLocationCoordinate2D] {
        points.map { point($0.0, $0.1) }
    }

    /// Points every 100 m eastwards from 0 to `length`.
    private static func straight(_ length: Double) -> [CLLocationCoordinate2D] {
        stride(from: 0, through: length, by: 100).map { point($0, 0) }
    }

    private static func isClose(_ actual: Double, _ expected: Double) -> Bool {
        abs(actual - expected) <= max(2, expected * 0.005)
    }

    @Test func tracksProgressAlongStraightRoute() {
        var progress = RouteProgress(coordinates: Self.straight(1000))
        let match = progress.update(with: Self.point(300, 5), threshold: Self.threshold)
        #expect(match?.isOnRoute == true)
        #expect(Self.isClose(progress.distanceAlongRoute, 300))
        #expect(Self.isClose(progress.remainingDistance, 700))
    }

    @Test func returnsNilWithoutRouteLine() {
        var progress = RouteProgress(coordinates: [Self.point(0, 0)])
        #expect(progress.update(with: Self.point(0, 0), threshold: Self.threshold) == nil)
    }

    @Test func reportsOffRouteWithoutAdvancing() {
        var progress = RouteProgress(coordinates: Self.straight(1000))
        let match = progress.update(with: Self.point(300, 200), threshold: Self.threshold)
        #expect(match?.isOnRoute == false)
        #expect(Self.isClose(match?.distanceFromRoute ?? 0, 200))
        #expect(progress.distanceAlongRoute == 0)
    }

    @Test func resumesAfterReturningToRoute() {
        var progress = RouteProgress(coordinates: Self.straight(1000))
        _ = progress.update(with: Self.point(300, 200), threshold: Self.threshold)
        let match = progress.update(with: Self.point(400, 0), threshold: Self.threshold)
        #expect(match?.isOnRoute == true)
        #expect(Self.isClose(progress.distanceAlongRoute, 400))
    }

    @Test func ignoresBackwardJitter() {
        var progress = RouteProgress(coordinates: Self.straight(1000))
        _ = progress.update(with: Self.point(500, 0), threshold: Self.threshold)
        let match = progress.update(with: Self.point(490, 0), threshold: Self.threshold)
        #expect(match?.isOnRoute == true)
        #expect(Self.isClose(progress.distanceAlongRoute, 500))
    }

    @Test func prefersFirstPassOnOutAndBackRoute() {
        // Out east along y=0 and back west 20 m north. The return leg is closer
        // to the rider but is a later pass and must not be chosen.
        let coordinates = Self.line([(0, 0), (200, 0), (200, 20), (0, 20)])
        var progress = RouteProgress(coordinates: coordinates)
        _ = progress.update(with: Self.point(50, 15), threshold: Self.threshold)
        #expect(Self.isClose(progress.distanceAlongRoute, 50))
    }

    @Test func advancesStepWhenCuttingCorner() {
        let coordinates = Self.line([(0, 0), (300, 0), (300, 300)])
        let stepEnds = Self.line([(300, 0), (300, 300)])
        var progress = RouteProgress(coordinates: coordinates, stepEnds: stepEnds)
        _ = progress.update(with: Self.point(200, 0), threshold: Self.threshold)
        #expect(progress.currentStepIndex == 0)
        #expect(Self.isClose(progress.distanceToStepEnd(at: 0), 100))
        // More than 20 m from the corner, but already on the next street.
        _ = progress.update(with: Self.point(295, 30), threshold: Self.threshold)
        #expect(progress.currentStepIndex == 1)
        #expect(Self.isClose(progress.distanceToStepEnd(at: 1), 270))
    }

    @Test func advancesStepShortlyBeforeManeuver() {
        let coordinates = Self.line([(0, 0), (300, 0), (300, 300)])
        let stepEnds = Self.line([(300, 0), (300, 300)])
        var progress = RouteProgress(coordinates: coordinates, stepEnds: stepEnds)
        _ = progress.update(with: Self.point(270, 0), threshold: Self.threshold)
        #expect(progress.currentStepIndex == 0)
        // Within 20 m of the turn the next instruction is shown.
        _ = progress.update(with: Self.point(290, 0), threshold: Self.threshold)
        #expect(progress.currentStepIndex == 1)
    }

    @Test func measuresStepDistanceAlongRoute() {
        // U-shape: the step end is about 200 m away in a straight line but 1150 m along the route.
        let coordinates = Self.line([(0, 0), (500, 0), (500, 200), (0, 200)])
        var progress = RouteProgress(coordinates: coordinates, stepEnds: [Self.point(0, 200)])
        _ = progress.update(with: Self.point(50, 0), threshold: Self.threshold)
        #expect(Self.isClose(progress.distanceToStepEnd(at: 0), 1150))
        #expect(Self.isClose(progress.remainingDistance, 1150))
    }

    @Test func placesStepEndsInOrderOnLoop() {
        let corners = [(400.0, 0.0), (400.0, 400.0), (0.0, 400.0), (0.0, 0.0)]
        let coordinates = Self.line([(0, 0)] + corners)
        var progress = RouteProgress(coordinates: coordinates, stepEnds: Self.line(corners))
        #expect(progress.stepEndDistances.count == 4)
        for (actual, expected) in zip(progress.stepEndDistances, [400.0, 800, 1200, 1600]) {
            #expect(Self.isClose(actual, expected))
        }
        for position in [(200.0, 0.0), (400.0, 200.0), (200.0, 400.0), (0.0, 200.0)] {
            _ = progress.update(with: Self.point(position.0, position.1), threshold: Self.threshold)
        }
        // Back near the start, the loop's end must not snap back to its beginning.
        _ = progress.update(with: Self.point(0, 20), threshold: Self.threshold)
        #expect(Self.isClose(progress.distanceAlongRoute, 1580))
        #expect(progress.currentStepIndex == 3)
    }

    @Test func reportsNextUnreachedWaypoint() {
        let legEnds = [
            RouteProgress.LegEnd(coordinateIndex: 5, waypointIndex: 1),
            RouteProgress.LegEnd(coordinateIndex: 8, waypointIndex: 2)
        ]
        var progress = RouteProgress(coordinates: Self.straight(1000), legEnds: legEnds)
        #expect(progress.nextWaypointIndex == 1)
        _ = progress.update(with: Self.point(400, 0), threshold: Self.threshold)
        #expect(progress.nextWaypointIndex == 1)
        _ = progress.update(with: Self.point(600, 0), threshold: Self.threshold)
        #expect(progress.nextWaypointIndex == 2)
        _ = progress.update(with: Self.point(900, 0), threshold: Self.threshold)
        #expect(progress.nextWaypointIndex == nil)
    }

    @Test func onlySearchesWithinLookahead() {
        var progress = RouteProgress(coordinates: Self.straight(2000))
        _ = progress.update(with: Self.point(400, 0), threshold: Self.threshold)
        _ = progress.update(with: Self.point(800, 0), threshold: Self.threshold)
        #expect(Self.isClose(progress.distanceAlongRoute, 800))
        // On the route line, but further ahead than the lookahead window.
        let match = progress.update(with: Self.point(1500, 0), threshold: Self.threshold)
        #expect(match?.isOnRoute == false)
        #expect(Self.isClose(progress.distanceAlongRoute, 800))
    }
}
