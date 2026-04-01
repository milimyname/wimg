import WidgetKit

struct WimgEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct WimgTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WimgEntry {
        WimgEntry(date: .now, data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (WimgEntry) -> Void) {
        completion(WimgEntry(date: .now, data: WidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WimgEntry>) -> Void) {
        let entry = WimgEntry(date: .now, data: WidgetData.load())
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}
