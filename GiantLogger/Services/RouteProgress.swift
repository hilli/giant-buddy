import CoreLocation
import MapKit

/// Tracks how far the rider has come along a navigation route, so the current
/// step and distances follow the rider instead of depending on passing close
/// to each maneuver point.
struct RouteProgress {
    struct LegEnd {
        let coordinateIndex: Int
        let waypointIndex: Int
    }

    struct Match {
        let isOnRoute: Bool
        let distanceFromRoute: CLLocationDistance
    }

    /// How far ahead of the current progress the route is searched for a match.
    static let lookahead: CLLocationDistance = 500
    /// A step is finished once its maneuver is this close ahead.
    static let stepAdvanceDistance: CLLocationDistance = 20

    let stepEndDistances: [CLLocationDistance]
    private(set) var distanceAlongRoute: CLLocationDistance = 0

    private let points: [MKMapPoint]
    private let cumulativeDistances: [CLLocationDistance]
    private let legEndDistances: [(distance: CLLocationDistance, waypointIndex: Int)]
    private var segmentIndex = 0

    init(
        coordinates: [CLLocationCoordinate2D] = [],
        stepEnds: [CLLocationCoordinate2D] = [],
        legEnds: [LegEnd] = []
    ) {
        let points = coordinates.map(MKMapPoint.init)
        var cumulative: [CLLocationDistance] = []
        cumulative.reserveCapacity(points.count)
        for index in points.indices {
            let previous = index == 0 ? 0 : cumulative[index - 1] + points[index - 1].distance(to: points[index])
            cumulative.append(previous)
        }
        self.points = points
        cumulativeDistances = cumulative

        var stepEndDistances: [CLLocationDistance] = []
        var searchStart = 0
        for stepEnd in stepEnds {
            let index = Self.nearestIndex(to: MKMapPoint(stepEnd), in: points, from: searchStart)
            stepEndDistances.append(index.map { cumulative[$0] } ?? 0)
            searchStart = index ?? searchStart
        }
        self.stepEndDistances = stepEndDistances

        legEndDistances = legEnds.compactMap { leg in
            guard cumulative.indices.contains(leg.coordinateIndex) else { return nil }
            return (cumulative[leg.coordinateIndex], leg.waypointIndex)
        }
    }

    var totalDistance: CLLocationDistance {
        cumulativeDistances.last ?? 0
    }

    var remainingDistance: CLLocationDistance {
        max(0, totalDistance - distanceAlongRoute)
    }

    /// The step whose maneuver comes next.
    var currentStepIndex: Int {
        stepEndDistances.firstIndex { $0 - distanceAlongRoute > Self.stepAdvanceDistance }
            ?? max(0, stepEndDistances.count - 1)
    }

    /// The first route waypoint the rider has not reached yet, for rejoining after going off route.
    var nextWaypointIndex: Int? {
        legEndDistances.first { $0.distance > distanceAlongRoute }?.waypointIndex
    }

    func distanceToStepEnd(at index: Int) -> CLLocationDistance {
        guard stepEndDistances.indices.contains(index) else { return 0 }
        return max(0, stepEndDistances[index] - distanceAlongRoute)
    }

    /// Matches `coordinate` to the route ahead and advances the progress.
    /// Returns nil when there is no route line to match against.
    mutating func update(with coordinate: CLLocationCoordinate2D, threshold: CLLocationDistance) -> Match? {
        guard points.count >= 2 else { return nil }

        let point = MKMapPoint(coordinate)
        let searchLimit = distanceAlongRoute + Self.lookahead
        var best: Projection?
        var closest = CLLocationDistance.greatestFiniteMagnitude

        for index in segmentIndex ..< (points.count - 1) {
            guard cumulativeDistances[index] <= searchLimit else { break }
            let projection = project(point, ontoSegment: index)
            closest = min(closest, projection.distance)
            if projection.distance <= threshold {
                if projection.distance < best?.distance ?? .infinity {
                    best = projection
                }
            } else if best != nil {
                // Only match within the first on-route stretch, so a later pass
                // along the same road (loops, out-and-back) is not chosen.
                break
            }
        }

        guard let best else {
            return Match(isOnRoute: false, distanceFromRoute: closest)
        }
        if best.along > distanceAlongRoute {
            distanceAlongRoute = best.along
            segmentIndex = best.segment
        }
        return Match(isOnRoute: true, distanceFromRoute: best.distance)
    }

    private struct Projection {
        let segment: Int
        let distance: CLLocationDistance
        let along: CLLocationDistance
    }

    private func project(_ point: MKMapPoint, ontoSegment index: Int) -> Projection {
        let start = points[index]
        let end = points[index + 1]
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let fraction = lengthSquared == 0
            ? 0
            : max(0, min(1, ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared))
        let projected = MKMapPoint(x: start.x + fraction * deltaX, y: start.y + fraction * deltaY)
        let segmentLength = cumulativeDistances[index + 1] - cumulativeDistances[index]
        return Projection(
            segment: index,
            distance: point.distance(to: projected),
            along: cumulativeDistances[index] + fraction * segmentLength
        )
    }

    private static func nearestIndex(to target: MKMapPoint, in points: [MKMapPoint], from start: Int) -> Int? {
        guard start < points.count else { return nil }
        var nearest: (index: Int, distance: CLLocationDistance)?
        for index in start ..< points.count {
            let distance = target.distance(to: points[index])
            if distance < nearest?.distance ?? .infinity {
                nearest = (index, distance)
            }
        }
        return nearest?.index
    }
}
