import SwiftUI
import WidgetKit

struct WimgWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: WimgEntry

    var body: some View {
        switch family {
        case .systemSmall:
            WimgSmallWidgetView(entry: entry)
        case .systemMedium:
            WimgMediumWidgetView(entry: entry)
        case .systemLarge:
            WimgLargeWidgetView(entry: entry)
        case .accessoryRectangular:
            WimgLockScreenWidgetView(entry: entry)
        default:
            WimgSmallWidgetView(entry: entry)
        }
    }
}

struct WimgWidget: Widget {
    let kind = "WimgWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WimgTimelineProvider()) { entry in
            WimgWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("wimg")
        .description("Verfügbares Einkommen, Sparquote & letzte Buchungen")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct wimgWidgetBundle: WidgetBundle {
    var body: some Widget {
        WimgWidget()
    }
}
