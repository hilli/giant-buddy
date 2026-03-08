import Foundation
import SwiftData

@Model
final class MaintenanceItem {
    var id: UUID = UUID()
    var componentName: String = ""
    var installDate: Date = Date.now
    var installOdometer: Double = 0
    var serviceIntervalKm: Double = 0
    var serviceIntervalDays: Int = 0
    var notes: String = ""
    var isActive: Bool = true

    init() {}

    init(componentName: String, installOdometer: Double, serviceIntervalKm: Double = 0, serviceIntervalDays: Int = 0) {
        self.componentName = componentName
        self.installOdometer = installOdometer
        self.serviceIntervalKm = serviceIntervalKm
        self.serviceIntervalDays = serviceIntervalDays
    }

    func kmSinceInstall(currentOdo: Double) -> Double {
        max(0, currentOdo - installOdometer)
    }

    var daysSinceInstall: Int {
        Calendar.current.dateComponents([.day], from: installDate, to: .now).day ?? 0
    }

    func isServiceDue(currentOdo: Double) -> Bool {
        if serviceIntervalKm > 0 && kmSinceInstall(currentOdo: currentOdo) >= serviceIntervalKm {
            return true
        }
        if serviceIntervalDays > 0 && daysSinceInstall >= serviceIntervalDays {
            return true
        }
        return false
    }

    func serviceProgress(currentOdo: Double) -> Double {
        var kmProgress: Double = 0
        var dayProgress: Double = 0
        var hasKm = false
        var hasDays = false

        if serviceIntervalKm > 0 {
            hasKm = true
            kmProgress = kmSinceInstall(currentOdo: currentOdo) / serviceIntervalKm
        }
        if serviceIntervalDays > 0 {
            hasDays = true
            dayProgress = Double(daysSinceInstall) / Double(serviceIntervalDays)
        }

        if hasKm && hasDays { return max(kmProgress, dayProgress) }
        if hasKm { return kmProgress }
        if hasDays { return dayProgress }
        return 0
    }
}

@Model
final class BatterySnapshot {
    var id: UUID = UUID()
    var date: Date = Date.now
    var capacityPercent: Int = 0
    var healthPercent: Int = 0
    var fullCapacityWh: Double = 0
    var chargeCycles: Int = 0
    var odometer: Double = 0

    init() {}

    init(capacityPercent: Int, healthPercent: Int, fullCapacityWh: Double, chargeCycles: Int, odometer: Double) {
        self.capacityPercent = capacityPercent
        self.healthPercent = healthPercent
        self.fullCapacityWh = fullCapacityWh
        self.chargeCycles = chargeCycles
        self.odometer = odometer
    }
}

@Model
final class ErrorLogEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var source: String = ""
    var errorCode: String = ""
    var odometer: Double = 0

    init() {}

    init(source: String, errorCode: String, odometer: Double) {
        self.source = source
        self.errorCode = errorCode
        self.odometer = odometer
    }
}
