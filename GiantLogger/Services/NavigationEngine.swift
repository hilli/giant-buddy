import Foundation
import CoreLocation
import MapKit
import AVFoundation
import UIKit

/// Turn-by-turn navigation engine that provides maneuver instructions,
/// voice guidance, and haptic feedback using MKDirections.
@MainActor
class NavigationEngine: ObservableObject {

    // MARK: - Types

    enum ManeuverType: String {
        case straight = "Continue straight"
        case turnLeft = "Turn left"
        case turnRight = "Turn right"
        case slightLeft = "Bear left"
        case slightRight = "Bear right"
        case sharpLeft = "Sharp left"
        case sharpRight = "Sharp right"
        case uTurn = "Make a U-turn"
        case arrive = "You have arrived"

        var sfSymbol: String {
            switch self {
            case .straight: return "arrow.up"
            case .turnLeft: return "arrow.turn.up.left"
            case .turnRight: return "arrow.turn.up.right"
            case .slightLeft: return "arrow.up.left"
            case .slightRight: return "arrow.up.right"
            case .sharpLeft: return "arrow.turn.down.left"
            case .sharpRight: return "arrow.turn.down.right"
            case .uTurn: return "arrow.uturn.down"
            case .arrive: return "flag.checkered"
            }
        }
    }

    struct NavigationInstruction: Identifiable {
        let id = UUID()
        let maneuverType: ManeuverType
        let distanceToManeuver: Double  // meters from step start
        let streetName: String?
        let coordinate: CLLocationCoordinate2D
    }

    // MARK: - Published State

    @Published var currentInstruction: NavigationInstruction?
    @Published var nextInstruction: NavigationInstruction?
    @Published var distanceToNextManeuver: Double = 0  // meters
    @Published var isRerouting = false
    @Published var hasArrived = false
    @Published var directionsAvailable = true
    @Published var rerouteFailed = false
    @Published var isOffRoute = false
    @Published var offRouteDistance: Double = 0
    @Published var activeRoute: Route?

    // MARK: - Settings

    @Published var voiceGuidanceEnabled: Bool = true
    @Published var hapticFeedbackEnabled: Bool = true

    // MARK: - Public State

    /// The computed route coordinates for map display.
    var navigationRouteCoordinates: [CLLocationCoordinate2D] { routeCoordinates }

    // MARK: - Private State

    private let synthesizer = AVSpeechSynthesizer()
    private var routeSteps: [MKRoute.Step] = []
    private var currentStepIndex: Int = 0
    private var mkRoute: MKRoute?
    private var lastAnnouncedStepIndex: Int = -1
    private var lastAnnouncedDistance: AnnouncementThreshold = .none
    private var lastHapticStepIndex: Int = -1
    private var offRouteStartTime: Date?
    private var destinationCoordinate: CLLocationCoordinate2D?
    private var lastUpdateLocation: CLLocation?
    private var routeCoordinates: [CLLocationCoordinate2D] = []
    private let watchConnectivity = WatchConnectivityManager.shared

    private let arrivalThreshold: Double = 30 // meters
    private let offRouteThreshold: Double = 100 // meters
    private let rerouteDelay: TimeInterval = 10
    private let significantMovement: Double = 3 // meters

    private enum AnnouncementThreshold {
        case none, far, near
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("NavigationEngine: Audio session setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Directions Calculation

    /// Calculate MKDirections for the given route, extracting turn-by-turn steps.
    /// Routes between key navigation waypoints only, avoiding excessive API calls
    /// for routes with many interpolated polyline coordinates.
    /// When `userLocation` is provided, navigation starts from the closest key waypoint
    /// with an initial leg from the user's position to that waypoint.
    func calculateDirections(for route: Route, from userLocation: CLLocation? = nil) async {
        let allWaypoints = route.sortedWaypoints
        guard allWaypoints.count >= 2 else { directionsAvailable = false; return }
        activeRoute = route
        destinationCoordinate = allWaypoints.last!.coordinate

        // Use only key navigation waypoints for MKDirections routing
        var navWaypoints = route.navigationWaypoints
        guard navWaypoints.count >= 2 else { directionsAvailable = false; return }

        // Determine which key waypoint to start from based on user proximity
        let insertUserLeg: Bool
        if let userLocation {
            var closestIndex = 0
            var closestDistance = Double.greatestFiniteMagnitude
            for (idx, wp) in navWaypoints.enumerated() {
                let dist = userLocation.distance(from: CLLocation(latitude: wp.latitude, longitude: wp.longitude))
                if dist < closestDistance {
                    closestDistance = dist
                    closestIndex = idx
                }
            }
            // If closest is the last waypoint, step back one so there's at least one leg
            let startIndex = min(closestIndex, navWaypoints.count - 2)
            navWaypoints = Array(navWaypoints[startIndex...])
            insertUserLeg = true
        } else {
            insertUserLeg = false
        }

        var allSteps: [MKRoute.Step] = []
        var allCoordinates: [CLLocationCoordinate2D] = []
        let lastLegIndex = navWaypoints.count - 2

        // First leg from user's current position to the closest key waypoint
        if insertUserLeg, let userLocation {
            let firstWP = navWaypoints.first!
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: firstWP.coordinate))
            request.transportType = .cycling

            let directions = MKDirections(request: request)
            if let response = try? await directions.calculate(),
               let leg = response.routes.first {
                var steps = leg.steps.filter { !$0.instructions.isEmpty }
                // Filter intermediate arrive steps from the user-to-start leg
                steps = steps.filter { step in
                    let lower = step.instructions.lowercased()
                    return !lower.contains("arrive") && !lower.contains("destination")
                }
                allSteps.append(contentsOf: steps)
                allCoordinates.append(contentsOf: leg.polyline.coordinates)
            }
        }

        for i in 0..<(navWaypoints.count - 1) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: navWaypoints[i].coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: navWaypoints[i+1].coordinate))
            request.transportType = .cycling

            let directions = MKDirections(request: request)
            do {
                let response = try await directions.calculate()
                if let route = response.routes.first {
                    var steps = route.steps.filter { !$0.instructions.isEmpty }
                    // Remove intermediate "arrive" steps so navigation continues past mid-route waypoints
                    if i < lastLegIndex {
                        steps = steps.filter { step in
                            let lower = step.instructions.lowercased()
                            return !lower.contains("arrive") && !lower.contains("destination")
                        }
                    }
                    allSteps.append(contentsOf: steps)
                    let coords = route.polyline.coordinates
                    if !allCoordinates.isEmpty && !coords.isEmpty {
                        allCoordinates.append(contentsOf: coords.dropFirst()) // avoid duplicate junction point
                    } else {
                        allCoordinates.append(contentsOf: coords)
                    }
                }
            } catch {
                // Try walking as fallback for this leg
                let walkRequest = MKDirections.Request()
                walkRequest.source = MKMapItem(placemark: MKPlacemark(coordinate: navWaypoints[i].coordinate))
                walkRequest.destination = MKMapItem(placemark: MKPlacemark(coordinate: navWaypoints[i+1].coordinate))
                walkRequest.transportType = .walking
                let walkDirections = MKDirections(request: walkRequest)
                if let response = try? await walkDirections.calculate(),
                   let route = response.routes.first {
                    var steps = route.steps.filter { !$0.instructions.isEmpty }
                    if i < lastLegIndex {
                        steps = steps.filter { step in
                            let lower = step.instructions.lowercased()
                            return !lower.contains("arrive") && !lower.contains("destination")
                        }
                    }
                    allSteps.append(contentsOf: steps)
                    let coords = route.polyline.coordinates
                    if !allCoordinates.isEmpty && !coords.isEmpty {
                        allCoordinates.append(contentsOf: coords.dropFirst())
                    } else {
                        allCoordinates.append(contentsOf: coords)
                    }
                }
            }
        }

        routeSteps = allSteps
        routeCoordinates = allCoordinates
        directionsAvailable = !allSteps.isEmpty
        currentStepIndex = 0
        lastAnnouncedStepIndex = -1
        lastAnnouncedDistance = .none
        lastHapticStepIndex = -1

        if directionsAvailable {
            updateInstructions()
            configureAudioSession()
        }
    }

    private func applyRoute(_ route: MKRoute) {
        mkRoute = route
        routeSteps = route.steps.filter { !$0.instructions.isEmpty }
        routeCoordinates = route.polyline.coordinates
        currentStepIndex = 0
        lastAnnouncedStepIndex = -1
        lastAnnouncedDistance = .none
        lastHapticStepIndex = -1
        directionsAvailable = true
        updateInstructions()
        configureAudioSession()
    }

    // MARK: - Location Updates

    /// Update navigation state based on user's current location.
    /// Only processes if user moved significantly since last update.
    func updateLocation(_ location: CLLocation) {
        if let last = lastUpdateLocation,
           location.distance(from: last) < significantMovement {
            return
        }
        lastUpdateLocation = location

        guard !routeSteps.isEmpty else { return }

        // Check arrival first
        if let dest = destinationCoordinate, checkArrival(at: location, destination: dest) {
            return
        }

        // Advance current step based on proximity
        advanceStepIfNeeded(location: location)

        // Update distance to next maneuver
        if currentStepIndex < routeSteps.count {
            let step = routeSteps[currentStepIndex]
            let stepEndCoord = stepEndCoordinate(for: step)
            distanceToNextManeuver = location.distance(
                from: CLLocation(latitude: stepEndCoord.latitude, longitude: stepEndCoord.longitude)
            )
        }

        updateInstructions()

        // Voice guidance
        handleVoiceGuidance()

        // Haptic feedback
        handleHapticFeedback()

        // Off-route / reroute detection
        handleOffRouteDetection(location: location)
    }

    private func advanceStepIfNeeded(location: CLLocation) {
        // If we're close to the end of the current step, advance
        while currentStepIndex < routeSteps.count - 1 {
            let step = routeSteps[currentStepIndex]
            let stepEnd = stepEndCoordinate(for: step)
            let distToEnd = location.distance(
                from: CLLocation(latitude: stepEnd.latitude, longitude: stepEnd.longitude)
            )
            // If within 20m of step endpoint, advance
            if distToEnd < 20 {
                currentStepIndex += 1
                lastAnnouncedDistance = .none
            } else {
                break
            }
        }
    }

    private func stepEndCoordinate(for step: MKRoute.Step) -> CLLocationCoordinate2D {
        return getPolylineEndCoordinate(step.polyline)
    }

    private func getPolylineEndCoordinate(_ polyline: MKPolyline) -> CLLocationCoordinate2D {
        let count = polyline.pointCount
        guard count > 0 else { return polyline.coordinate }
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords[count - 1]
    }

    private func getPolylineStartCoordinate(_ polyline: MKPolyline) -> CLLocationCoordinate2D {
        let count = polyline.pointCount
        guard count > 0 else { return polyline.coordinate }
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: min(2, count)))
        return coords[0]
    }

    // MARK: - Instructions

    private func updateInstructions() {
        guard !routeSteps.isEmpty else {
            currentInstruction = nil
            nextInstruction = nil
            return
        }

        if currentStepIndex < routeSteps.count {
            let step = routeSteps[currentStepIndex]
            let maneuver = maneuverTypeFromInstructions(step.instructions, stepIndex: currentStepIndex)
            currentInstruction = NavigationInstruction(
                maneuverType: maneuver,
                distanceToManeuver: distanceToNextManeuver,
                streetName: extractStreetName(from: step.instructions),
                coordinate: getPolylineStartCoordinate(step.polyline)
            )
        }

        if currentStepIndex + 1 < routeSteps.count {
            let nextStep = routeSteps[currentStepIndex + 1]
            let maneuver = maneuverTypeFromInstructions(nextStep.instructions, stepIndex: currentStepIndex + 1)
            nextInstruction = NavigationInstruction(
                maneuverType: maneuver,
                distanceToManeuver: nextStep.distance,
                streetName: extractStreetName(from: nextStep.instructions),
                coordinate: getPolylineStartCoordinate(nextStep.polyline)
            )
        } else {
            nextInstruction = nil
        }

        // Send navigation update to Apple Watch
        if let instruction = currentInstruction {
            watchConnectivity.sendNavigationUpdate(
                instruction: instruction.maneuverType.rawValue,
                distance: distanceToNextManeuver,
                symbol: instruction.maneuverType.sfSymbol,
                street: instruction.streetName,
                isNavigating: true
            )
        }
    }

    // MARK: - Maneuver Detection

    /// Determine maneuver type from MKRoute.Step instructions and bearing analysis.
    private func maneuverTypeFromInstructions(_ instructions: String, stepIndex: Int) -> ManeuverType {
        let lower = instructions.lowercased()

        // Direct text matching from MKRoute instructions
        if lower.contains("arrive") || lower.contains("destination") {
            return .arrive
        }
        if lower.contains("u-turn") || lower.contains("u turn") {
            return .uTurn
        }
        if lower.contains("sharp left") {
            return .sharpLeft
        }
        if lower.contains("sharp right") {
            return .sharpRight
        }
        if lower.contains("slight left") || lower.contains("bear left") || lower.contains("keep left") {
            return .slightLeft
        }
        if lower.contains("slight right") || lower.contains("bear right") || lower.contains("keep right") {
            return .slightRight
        }
        if lower.contains("turn left") || lower.contains("left on") {
            return .turnLeft
        }
        if lower.contains("turn right") || lower.contains("right on") {
            return .turnRight
        }

        // Fall back to bearing analysis between steps
        if stepIndex > 0, stepIndex < routeSteps.count {
            let prevStep = routeSteps[stepIndex - 1]
            let curStep = routeSteps[stepIndex]
            let prevEnd = getPolylineEndCoordinate(prevStep.polyline)
            let prevStart: CLLocationCoordinate2D
            let prevCount = prevStep.polyline.pointCount
            if prevCount >= 2 {
                var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: prevCount)
                prevStep.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: prevCount))
                prevStart = coords[max(0, prevCount - 2)]
            } else {
                prevStart = getPolylineStartCoordinate(prevStep.polyline)
            }

            let curStart = getPolylineStartCoordinate(curStep.polyline)
            let curCount = curStep.polyline.pointCount
            let curEnd: CLLocationCoordinate2D
            if curCount >= 2 {
                var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: curCount)
                curStep.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: curCount))
                curEnd = coords[min(1, curCount - 1)]
            } else {
                curEnd = getPolylineEndCoordinate(curStep.polyline)
            }

            let fromBearing = bearing(from: prevStart, to: prevEnd)
            let toBearing = bearing(from: curStart, to: curEnd)
            return maneuverType(fromBearing: fromBearing, toBearing: toBearing)
        }

        return .straight
    }

    /// Determine maneuver type from bearing change between route segments.
    func maneuverType(fromBearing: Double, toBearing: Double) -> ManeuverType {
        var angle = toBearing - fromBearing
        // Normalize to -180...180
        while angle > 180 { angle -= 360 }
        while angle <= -180 { angle += 360 }

        switch angle {
        case -180 ... -135: return .sharpLeft
        case -135 ... -45: return .turnLeft
        case -45 ... -15: return .slightLeft
        case -15 ... 15: return .straight
        case 15 ... 45: return .slightRight
        case 45 ... 135: return .turnRight
        case 135 ... 180: return .sharpRight
        default: return .uTurn
        }
    }

    private func extractStreetName(from instructions: String) -> String? {
        // Common patterns: "Turn left onto Elm Street", "Continue on Main Road"
        let patterns = ["onto ", "on ", "along "]
        for pattern in patterns {
            if let range = instructions.range(of: pattern, options: .caseInsensitive) {
                let street = String(instructions[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return street.isEmpty ? nil : street
            }
        }
        return nil
    }

    // MARK: - Voice Guidance

    func announceInstruction(_ instruction: NavigationInstruction) {
        guard voiceGuidanceEnabled else { return }

        var text: String
        if instruction.maneuverType == .arrive {
            text = "You have arrived at your destination"
        } else {
            let distText = formatSpokenDistance(instruction.distanceToManeuver)
            text = "In \(distText), \(instruction.maneuverType.rawValue.lowercased())"
            if let street = instruction.streetName {
                text += " onto \(street)"
            }
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        if let voiceLanguage = Locale.current.language.languageCode?.identifier {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }

        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    private func announceImmediateTurn(_ instruction: NavigationInstruction) {
        guard voiceGuidanceEnabled else { return }

        var text = instruction.maneuverType.rawValue
        if let street = instruction.streetName {
            text += " onto \(street)"
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 0.8
        if let voiceLanguage = Locale.current.language.languageCode?.identifier {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }

        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    func stopVoice() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func formatSpokenDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f kilometers", meters / 1000)
        }
        let rounded = Int((meters / 50).rounded()) * 50
        return "\(max(50, rounded)) meters"
    }

    private func handleVoiceGuidance() {
        guard voiceGuidanceEnabled, let instruction = currentInstruction else { return }
        guard instruction.maneuverType != .straight || currentStepIndex != lastAnnouncedStepIndex else { return }

        let distance = distanceToNextManeuver

        if distance <= 200 && distance > 50 && lastAnnouncedDistance != .far {
            // "In 200 meters, turn left"
            lastAnnouncedDistance = .far
            lastAnnouncedStepIndex = currentStepIndex
            announceInstruction(instruction)
        } else if distance <= 50 && lastAnnouncedDistance != .near {
            // "Turn left"
            lastAnnouncedDistance = .near
            lastAnnouncedStepIndex = currentStepIndex
            announceImmediateTurn(instruction)
        }
    }

    // MARK: - Haptic Feedback

    func triggerTurnHaptic() {
        guard hapticFeedbackEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
    }

    private func triggerArrivalHaptic() {
        guard hapticFeedbackEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    private func handleHapticFeedback() {
        guard hapticFeedbackEnabled else { return }
        guard currentStepIndex != lastHapticStepIndex else { return }

        if distanceToNextManeuver <= 50 {
            lastHapticStepIndex = currentStepIndex
            triggerTurnHaptic()
        }
    }

    // MARK: - Re-routing

    private func handleOffRouteDetection(location: CLLocation) {
        guard !routeCoordinates.isEmpty else { return }

        let locationPoint = MKMapPoint(location.coordinate)
        var minDist = Double.greatestFiniteMagnitude
        for i in 0..<(routeCoordinates.count - 1) {
            let start = MKMapPoint(routeCoordinates[i])
            let end = MKMapPoint(routeCoordinates[i + 1])
            let dist = distanceFromPointToSegment(point: locationPoint, segStart: start, segEnd: end)
            minDist = min(minDist, dist)
        }

        offRouteDistance = minDist
        isOffRoute = minDist > offRouteThreshold

        if minDist > offRouteThreshold {
            if offRouteStartTime == nil {
                offRouteStartTime = Date()
            } else if let start = offRouteStartTime,
                      Date().timeIntervalSince(start) > rerouteDelay,
                      let dest = destinationCoordinate {
                offRouteStartTime = nil
                Task {
                    await reroute(from: location, to: dest)
                }
            }
        } else {
            offRouteStartTime = nil
        }
    }

    private func distanceToPolyline(point: MKMapPoint, polyline: MKPolyline) -> Double {
        let count = polyline.pointCount
        guard count >= 2 else {
            return point.distance(to: MKMapPoint(polyline.coordinate))
        }

        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))

        var minDist = Double.greatestFiniteMagnitude
        for i in 0..<(count - 1) {
            let start = MKMapPoint(coords[i])
            let end = MKMapPoint(coords[i + 1])
            let dist = distanceFromPointToSegment(point: point, segStart: start, segEnd: end)
            minDist = min(minDist, dist)
        }
        return minDist
    }

    private func distanceFromPointToSegment(point: MKMapPoint, segStart: MKMapPoint, segEnd: MKMapPoint) -> Double {
        let dx = segEnd.x - segStart.x
        let dy = segEnd.y - segStart.y
        let lengthSq = dx * dx + dy * dy

        if lengthSq == 0 {
            return point.distance(to: segStart)
        }

        let t = max(0, min(1,
            ((point.x - segStart.x) * dx + (point.y - segStart.y) * dy) / lengthSq
        ))

        let projected = MKMapPoint(x: segStart.x + t * dx, y: segStart.y + t * dy)
        return point.distance(to: projected)
    }

    /// Recalculate directions from current location to the destination.
    func reroute(from location: CLLocation, to destination: CLLocationCoordinate2D) async {
        isRerouting = true
        rerouteFailed = false

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .cycling

        let directions = MKDirections(request: request)

        do {
            let response = try await directions.calculate()
            if let route = response.routes.first {
                applyRoute(route)
                isRerouting = false
                return
            }
        } catch {
            print("NavigationEngine: Re-route cycling failed: \(error.localizedDescription)")
        }

        // Fallback to walking with fresh request
        let walkingRequest = MKDirections.Request()
        walkingRequest.source = request.source
        walkingRequest.destination = request.destination
        walkingRequest.transportType = .walking
        let fallbackDirections = MKDirections(request: walkingRequest)
        do {
            let response = try await fallbackDirections.calculate()
            if let route = response.routes.first {
                applyRoute(route)
                isRerouting = false
                return
            }
        } catch {
            print("NavigationEngine: Re-route walking also failed: \(error.localizedDescription)")
        }

        rerouteFailed = true
        isRerouting = false
    }

    // MARK: - Arrival Detection

    /// Returns true if the user has arrived at the destination.
    func checkArrival(at location: CLLocation, destination: CLLocationCoordinate2D) -> Bool {
        let destLocation = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distance = location.distance(from: destLocation)

        if distance <= arrivalThreshold && !hasArrived {
            hasArrived = true
            triggerArrivalHaptic()

            if voiceGuidanceEnabled {
                let arrival = NavigationInstruction(
                    maneuverType: .arrive,
                    distanceToManeuver: 0,
                    streetName: nil,
                    coordinate: destination
                )
                announceInstruction(arrival)
            }
            return true
        }
        return hasArrived
    }

    // MARK: - Bearing Calculation

    /// Compute bearing in degrees between two coordinates.
    func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    // MARK: - Cleanup

    func stop() {
        stopVoice()
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("NavigationEngine: Audio session deactivation failed: \(error.localizedDescription)")
        }
        activeRoute = nil
        routeSteps = []
        routeCoordinates = []
        currentInstruction = nil
        nextInstruction = nil
        hasArrived = false
        isRerouting = false
        rerouteFailed = false
        isOffRoute = false
        offRouteDistance = 0

        // Notify Apple Watch that navigation ended
        watchConnectivity.sendNavigationUpdate(
            instruction: "",
            distance: 0,
            symbol: "arrow.up",
            street: nil,
            isNavigating: false
        )
    }
}

// MARK: - MKPolyline Extension

extension MKPolyline {
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
