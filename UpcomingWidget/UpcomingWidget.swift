//
//  UpcomingWidget.swift
//  UpcomingWidget
//
//

import WidgetKit
import SwiftUI

struct UpcomingWidget: Widget {
    let kind: String = "UpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingTimelineProvider()) { entry in
            UpcomingWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Releases")
        .description("See your upcoming movie and TV show releases.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct UpcomingWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: UpcomingEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

#Preview(as: .systemSmall) {
    UpcomingWidget()
} timeline: {
    UpcomingEntry.placeholder
}

#Preview(as: .systemMedium) {
    UpcomingWidget()
} timeline: {
    UpcomingEntry.placeholder
}

#Preview(as: .systemLarge) {
    UpcomingWidget()
} timeline: {
    UpcomingEntry.placeholder
}
