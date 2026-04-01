import SwiftUI
import WidgetKit

struct WimgSmallWidget: Widget {
    let kind = "WimgSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            WimgSmallWidgetView(entry: entry)
        }
        .configurationDisplayName("wimg")
        .description("Verfügbares Einkommen und Sparquote")
        .supportedFamilies([.systemSmall])
    }
}

struct WimgMediumWidget: Widget {
    let kind = "WimgMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            WimgMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("wimg")
        .description("Einkommen, Sparquote und nächste Zahlung")
        .supportedFamilies([.systemMedium])
    }
}

struct WimgLargeWidget: Widget {
    let kind = "WimgLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            WimgLargeWidgetView(entry: entry)
        }
        .configurationDisplayName("wimg")
        .description("Übersicht mit letzten Transaktionen")
        .supportedFamilies([.systemLarge])
    }
}

struct WimgLockScreenWidget: Widget {
    let kind = "WimgLockScreenWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            WimgLockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("wimg")
        .description("Verfügbar auf dem Sperrbildschirm")
        .supportedFamilies([.accessoryRectangular])
    }
}

@main
struct wimgWidgetBundle: WidgetBundle {
    var body: some Widget {
        WimgSmallWidget()
        WimgMediumWidget()
        WimgLargeWidget()
        WimgLockScreenWidget()
    }
}
