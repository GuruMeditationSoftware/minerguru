import SwiftUI
import WidgetKit

@main
struct MinerGuruWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FleetWidget()
        MinerWidget()
        SoloWidget()
        PowerWidget()
        if #available(macOS 26.0, *) {
            FleetControl()
            NightModeControl()
            AlertsControl()
        }
    }
}
