import Foundation
import CoreLocation

// MARK: - GPX Parser

enum GPXParser {

    enum GPXError: LocalizedError {
        case invalidData
        case noTrackPoints
        case parsingFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidData:
                return "The file does not contain valid GPX data."
            case .noTrackPoints:
                return "The GPX file contains no track or route points."
            case .parsingFailed(let detail):
                return "GPX parsing failed: \(detail)"
            }
        }
    }

    /// Parse GPX data into a Route with waypoints.
    /// Supports both <trk>/<trkseg>/<trkpt> and <rte>/<rtept> formats.
    static func parse(data: Data) throws -> Route {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            let errorMsg = parser.parserError?.localizedDescription ?? "Unknown XML error"
            throw GPXError.parsingFailed(errorMsg)
        }

        guard !delegate.points.isEmpty else {
            throw GPXError.noTrackPoints
        }

        let route = Route(name: delegate.trackName ?? "Imported Route", source: "gpx_import")

        var waypoints: [RouteWaypoint] = []
        for (index, point) in delegate.points.enumerated() {
            let waypoint = RouteWaypoint(
                index: index,
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                name: point.name,
                timestamp: point.timestamp
            )
            waypoint.route = route
            waypoints.append(waypoint)
        }

        route.waypoints = waypoints
        route.recalculateStats()

        return route
    }
}

// MARK: - Parsed Point

private struct ParsedPoint {
    let latitude: Double
    let longitude: Double
    var altitude: Double = 0
    var name: String?
    var timestamp: Date?
}

// MARK: - XML Parser Delegate

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var points: [ParsedPoint] = []
    var trackName: String?

    private var currentPoint: ParsedPoint?
    private var currentElement = ""
    private var currentText = ""

    // Track nesting: gpx > trk > trkseg > trkpt  or  gpx > rte > rtept
    private var insideTrack = false
    private var insideRoute = false
    private var insidePoint = false
    private var insideMetadata = false
    private var hasTrackName = false

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "metadata":
            insideMetadata = true

        case "trk":
            insideTrack = true

        case "rte":
            insideRoute = true

        case "trkpt", "rtept":
            guard let latStr = attributeDict["lat"],
                  let lonStr = attributeDict["lon"],
                  let lat = Double(latStr),
                  let lon = Double(lonStr) else {
                return
            }
            currentPoint = ParsedPoint(latitude: lat, longitude: lon)
            insidePoint = true

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    // swiftlint:disable:next cyclomatic_complexity
    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "metadata":
            insideMetadata = false

        case "name":
            if insidePoint, !text.isEmpty {
                currentPoint?.name = text
            } else if isTrackOrRouteName(text: text) {
                trackName = text
                hasTrackName = true
            }

        case "ele":
            if insidePoint, let alt = Double(text) {
                currentPoint?.altitude = alt
            }

        case "time":
            if insidePoint {
                let date = Self.isoFormatter.date(from: text) ?? Self.isoFormatterNoFrac.date(from: text)
                currentPoint?.timestamp = date
            }

        case "trkpt", "rtept":
            if let point = currentPoint {
                points.append(point)
            }
            currentPoint = nil
            insidePoint = false

        case "trk":
            insideTrack = false

        case "rte":
            insideRoute = false

        default:
            break
        }

        currentText = ""
    }

    private func isTrackOrRouteName(text: String) -> Bool {
        (insideTrack || insideRoute) && !insidePoint && !insideMetadata && !hasTrackName && !text.isEmpty
    }
}
