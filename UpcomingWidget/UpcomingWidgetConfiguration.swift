import AppIntents
import WidgetKit

enum ReleaseWidgetFilter: String, AppEnum {
    case all, movies, shows
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Releases"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .all: "Movies and TV Shows", .movies: "Movies", .shows: "TV Shows"
    ]
}

struct UpcomingWidgetConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Upcoming Releases"
    static var description = IntentDescription("Choose which releases appear in this widget.")
    @Parameter(title: "Show", default: .all) var filter: ReleaseWidgetFilter
}

struct ConfigurableUpcomingProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry { .placeholder }

    func snapshot(for configuration: UpcomingWidgetConfiguration, in context: Context) async -> UpcomingEntry {
        entry(configuration, preview: context.isPreview)
    }

    func timeline(for configuration: UpcomingWidgetConfiguration, in context: Context) async -> Timeline<UpcomingEntry> {
        Timeline(entries: [entry(configuration)], policy: .after(Date().addingTimeInterval(4 * 3600)))
    }

    private func entry(_ configuration: UpcomingWidgetConfiguration, preview: Bool = false) -> UpcomingEntry {
        let source = preview ? UpcomingEntry.placeholder.events : WidgetEvent.loadUpcomingEvents()
        let events = source.filter { event in
            switch configuration.filter {
            case .all: return true
            case .movies: return event.isMovie
            case .shows: return !event.isMovie
            }
        }
        return UpcomingEntry(date: Date(), events: events, isConfigured: preview || WidgetEvent.isConfigured())
    }
}
