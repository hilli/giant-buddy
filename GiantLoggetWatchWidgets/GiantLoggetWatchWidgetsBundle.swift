import WidgetKit
import SwiftUI

@main
struct GiantLoggetWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BatteryComplication()
        RangeComplication()
    }
}
