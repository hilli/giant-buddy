import Foundation

/// Export rides as CSV or GPX files.
enum ExportService {

    // MARK: - CSV Export (compatible with ESP32 format + GPS columns)

    static func exportCSV(ride: Ride) -> String {
        let header = "timestamp,speed_kmh,cadence_rpm,torque_nm,watts,battery_pct,distance_km,ride_time_s,range_km,error,latitude,longitude,altitude,gps_speed_ms,course,packet_log"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let rows = ride.samples.sorted { $0.timestamp < $1.timestamp }.map { s in
            [
                formatter.string(from: s.timestamp),
                String(format: "%.1f", s.speed),
                String(format: "%.1f", s.cadence),
                String(format: "%.2f", s.torque),
                String(format: "%.1f", s.watts),
                "\(s.batteryPercent)",
                String(format: "%.1f", s.distance),
                "\(s.rideTime)",
                "\(s.range)",
                "\(s.errorCode)",
                String(format: "%.6f", s.latitude),
                String(format: "%.6f", s.longitude),
                String(format: "%.1f", s.altitude),
                String(format: "%.1f", s.gpsSpeed),
                String(format: "%.0f", s.course),
                "\"\(s.packetLog.replacingOccurrences(of: "\"", with: "\"\""))\"",
            ].joined(separator: ",")
        }

        return ([header] + rows).joined(separator: "\n")
    }

    // MARK: - GPX Export

    static func exportGPX(ride: Ride) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let dateStr = DateFormatter.localizedString(from: ride.startDate, dateStyle: .medium, timeStyle: .short)

        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Giant Logger iOS"
          xmlns="http://www.topografix.com/GPX/1/1"
          xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <metadata>
            <name>Giant E-Bike Ride \(dateStr)</name>
            <time>\(formatter.string(from: ride.startDate))</time>
          </metadata>
          <trk>
            <name>Ride \(dateStr)</name>
            <trkseg>
        """

        for sample in ride.samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard sample.latitude != 0 || sample.longitude != 0 else { continue }
            gpx += """

                  <trkpt lat="\(String(format: "%.6f", sample.latitude))" lon="\(String(format: "%.6f", sample.longitude))">
                    <ele>\(String(format: "%.1f", sample.altitude))</ele>
                    <time>\(formatter.string(from: sample.timestamp))</time>
                    <extensions>
                      <gpxtpx:TrackPointExtension>
                        <gpxtpx:speed>\(String(format: "%.1f", sample.speed / 3.6))</gpxtpx:speed>
                        <gpxtpx:hr>\(sample.batteryPercent)</gpxtpx:hr>
                      </gpxtpx:TrackPointExtension>
                      <power>\(String(format: "%.0f", sample.watts))</power>
                      <cadence>\(String(format: "%.0f", sample.cadence))</cadence>
                    </extensions>
                  </trkpt>
            """
        }

        gpx += """

            </trkseg>
          </trk>
        </gpx>
        """

        return gpx
    }

    // MARK: - File URLs

    static func writeToTempFile(content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
