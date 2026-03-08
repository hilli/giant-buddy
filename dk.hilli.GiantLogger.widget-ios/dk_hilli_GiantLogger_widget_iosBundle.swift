//
//  dk_hilli_GiantLogger_widget_iosBundle.swift
//  dk.hilli.GiantLogger.widget-ios
//
//  Created by Jens Hilligsøe on 08/03/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

@main
struct dk_hilli_GiantLogger_widget_iosBundle: WidgetBundle {
    var body: some Widget {
        dk_hilli_GiantLogger_widget_ios()
        dk_hilli_GiantLogger_widget_iosControl()
        RideLiveActivity()
    }
}
