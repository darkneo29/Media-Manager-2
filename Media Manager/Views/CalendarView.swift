//
//  CalendarView.swift
//  Media Manager
//
//  Calendar view showing upcoming movie releases and TV show air dates.
//

import SwiftUI

// MARK: - Static DateFormatters (avoid repeated allocations)

private enum CalendarFormatters {
    static let monthYear: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let todayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Today,' MMMM d"
        return formatter
    }()

    static let tomorrowFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "'Tomorrow,' MMMM d"
        return formatter
    }()

    static let weekdayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
}

// MARK: - Cached Day Data (pre-computed for grid)

struct CalendarDayData: Identifiable, Equatable {
    let id: Date
    let date: Date
    let isCurrentMonth: Bool
    let movieCount: Int
    let tvShowCount: Int

    var hasEvents: Bool { movieCount > 0 || tvShowCount > 0 }
}

struct CalendarView: View {
    @ObservedObject private var libraryState = LibraryStateManager.shared
    @ObservedObject private var releaseRadar = ReleaseRadarService.shared
    @State private var selectedDate: Date = Date()
    @State private var displayedMonth: Date = Date()
    @State private var navigationPath = NavigationPath()

    // MARK: - Cached Event Data

    /// Cached events built from library data
    @State private var cachedEvents: [CalendarEvent] = []

    /// Events indexed by date components for O(1) lookup
    @State private var eventsByDate: [DateComponents: [CalendarEvent]] = [:]

    /// Pre-computed day data for the current month grid
    @State private var cachedDayData: [CalendarDayData] = []

    /// Track data version to detect changes
    @State private var lastMoviesHash: Int = 0
    @State private var lastShowsHash: Int = 0
    @State private var lastDisplayedMonth: Date?

    private let calendar = Calendar.current
    private let daysOfWeek = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    // MARK: - Computed Properties (using cache)

    private var eventsForSelectedDate: [CalendarEvent] {
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        return (eventsByDate[components] ?? [])
            .filter(releaseRadar.isEnabled(for:))
            .sorted(by: releaseRadarSort)
    }

    private var monthTitle: String {
        CalendarFormatters.monthYear.string(from: displayedMonth)
    }

    private var selectedDateFormatted: String {
        if calendar.isDateInToday(selectedDate) {
            return CalendarFormatters.todayFormat.string(from: selectedDate)
        } else if calendar.isDateInTomorrow(selectedDate) {
            return CalendarFormatters.tomorrowFormat.string(from: selectedDate)
        } else {
            return CalendarFormatters.weekdayFormat.string(from: selectedDate)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $navigationPath) {
            #if os(tvOS)
            tvOSCalendarLayout
            #else
            iOSCalendarLayout
            #endif
        }
    }

    // MARK: - tvOS Layout (No Scrolling)

    #if os(tvOS)
    private var tvOSCalendarLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left side: Calendar
                VStack(spacing: AppSpacing.lg) {
                    // Month navigation
                    tvOSCalendarHeader

                    ReleaseRadarFilterBar(enabledFilters: releaseRadar.enabledFilters) { filter in
                        toggleReleaseRadarFilter(filter)
                    }

                    // Days of week
                    tvOSDaysOfWeekHeader

                // Calendar grid
                tvOSCalendarGrid

                // Legend
                tvOSCalendarLegend

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, TVSizing.contentPadding)
            .padding(.trailing, AppSpacing.lg)
            .padding(.top, AppSpacing.xl)

            // Divider
            Rectangle()
                .fill(ColorPalette.divider)
                .frame(width: 2)
                .padding(.vertical, AppSpacing.xl)

            // Right side: Events for selected date
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                tvOSSelectedDateSection
            }
            .frame(width: 500)
            .padding(.leading, AppSpacing.lg)
            .padding(.trailing, TVSizing.contentPadding)
            .padding(.top, AppSpacing.xl)
        }
        .background(ColorPalette.backgroundDark)
        .navigationTitle("Calendar")
        .navigationDestination(for: Movie.self) { movie in
            MovieDetailView(movie: movie)
        }
        .navigationDestination(for: TVShow.self) { show in
            TVShowDetailView(show: show)
        }
        .onAppear {
            if cachedDayData.isEmpty {
                rebuildEventCacheIfNeeded(movies: libraryState.movies, tvShows: libraryState.tvShows)
            }
            Task {
                await libraryState.loadAll()
            }
        }
        .onChange(of: libraryState.movies) { _, newMovies in
            rebuildEventCacheIfNeeded(movies: newMovies, tvShows: libraryState.tvShows)
        }
        .onChange(of: libraryState.tvShows) { _, newShows in
            rebuildEventCacheIfNeeded(movies: libraryState.movies, tvShows: newShows)
        }
        .onChange(of: displayedMonth) { _, _ in
            rebuildDayDataCache()
        }
        .onChange(of: releaseRadar.enabledFilters) { _, _ in
            rebuildDayDataCache()
            syncWidgetData()
        }
    }

    private var tvOSCalendarHeader: some View {
        HStack(spacing: AppSpacing.xl) {
            Button {
                withAnimation { goToPreviousMonth() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 60, height: 60)
            }

            Text(monthTitle)
                .font(.system(size: 42, weight: .bold))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .frame(minWidth: 300)

            Button {
                withAnimation { goToNextMonth() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 60, height: 60)
            }

            Spacer()

            Button {
                withAnimation {
                    selectedDate = Date()
                    displayedMonth = Date()
                }
            } label: {
                Text("Today")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.sm)
            }
        }
    }

    private var tvOSDaysOfWeekHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var tvOSCalendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(cachedDayData) { dayData in
                let isSelected = calendar.isDate(dayData.date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(dayData.date)

                TVCalendarDayCell(
                    date: dayData.date,
                    isCurrentMonth: dayData.isCurrentMonth,
                    isSelected: isSelected,
                    isToday: isToday,
                    movieCount: dayData.movieCount,
                    tvShowCount: dayData.tvShowCount
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = dayData.date
                    }
                }
            }
        }
    }

    private var tvOSCalendarLegend: some View {
        HStack(spacing: AppSpacing.xl) {
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(ColorPalette.primary)
                    .frame(width: 16, height: 16)
                Text("Movies")
                    .font(.system(size: 22))
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }

            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(ColorPalette.secondary)
                    .frame(width: 16, height: 16)
                Text("TV Shows")
                    .font(.system(size: 22))
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }
        }
    }

    private var tvOSSelectedDateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Date Header
            Text(selectedDateFormatted)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(ColorPalette.textPrimaryDark)

            if eventsForSelectedDate.isEmpty {
                // Empty State
                VStack(spacing: AppSpacing.lg) {
                    Spacer()

                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 80))
                        .foregroundColor(ColorPalette.textMutedDark)

                    Text("No releases scheduled")
                        .font(.system(size: 28))
                        .foregroundColor(ColorPalette.textSecondaryDark)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                // Events List (max 5 visible without scroll)
                VStack(spacing: AppSpacing.md) {
                    ForEach(eventsForSelectedDate.prefix(5)) { event in
                        TVCalendarEventCard(
                            event: event,
                            isFollowed: releaseRadar.isFollowing(event: event)
                        ) {
                            navigateToDetail(for: event)
                        }
                    }

                    // Show count if more events
                    if eventsForSelectedDate.count > 5 {
                        Text("+\(eventsForSelectedDate.count - 5) more")
                            .font(.system(size: 20))
                            .foregroundColor(ColorPalette.textMutedDark)
                            .frame(maxWidth: .infinity)
                            .padding(.top, AppSpacing.sm)
                    }
                }

                Spacer()
            }
        }
    }
    #endif

    // MARK: - iOS Layout

    #if !os(tvOS)
    private var iOSCalendarLayout: some View {
        ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Calendar Header
                    calendarHeader

                    ReleaseRadarFilterBar(enabledFilters: releaseRadar.enabledFilters) { filter in
                        toggleReleaseRadarFilter(filter)
                    }

                    // Days of Week Header
                    daysOfWeekHeader

                // Calendar Grid
                calendarGrid

                // Legend
                calendarLegend

                // Divider
                Rectangle()
                    .fill(ColorPalette.divider)
                    .frame(height: 1)
                    .padding(.horizontal, AppSpacing.md)

                // Selected Date Events
                selectedDateSection
            }
            .padding(.vertical, AppSpacing.md)
        }
        .background(ColorPalette.backgroundDark)
        .navigationTitle("Calendar")
        .navBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Today") {
                    withAnimation {
                        selectedDate = Date()
                        displayedMonth = Date()
                    }
                }
                .font(AppTypography.subheadline(.semibold))
                .foregroundColor(ColorPalette.secondary)
            }
        }
        .navigationDestination(for: Movie.self) { movie in
            MovieDetailView(movie: movie)
        }
        .navigationDestination(for: TVShow.self) { show in
            TVShowDetailView(show: show)
        }
        .refreshable {
            await refreshData()
        }
        .onAppear {
            // Initialize cache with existing data if available
            if cachedDayData.isEmpty {
                rebuildEventCacheIfNeeded(movies: libraryState.movies, tvShows: libraryState.tvShows)
            }
            Task {
                await libraryState.loadAll()
            }
        }
        .onChange(of: libraryState.movies) { _, newMovies in
            rebuildEventCacheIfNeeded(movies: newMovies, tvShows: libraryState.tvShows)
        }
        .onChange(of: libraryState.tvShows) { _, newShows in
            rebuildEventCacheIfNeeded(movies: libraryState.movies, tvShows: newShows)
        }
        .onChange(of: displayedMonth) { _, _ in
            rebuildDayDataCache()
        }
        .onChange(of: releaseRadar.enabledFilters) { _, _ in
            rebuildDayDataCache()
            syncWidgetData()
        }
    }
    #endif

    // MARK: - Cache Management

    /// Rebuild the events cache if the underlying data has changed
    private func rebuildEventCacheIfNeeded(movies: [Movie], tvShows: [TVShow]) {
        let moviesHash = movies.hashValue
        let showsHash = tvShows.hashValue

        // Only rebuild if data actually changed
        guard moviesHash != lastMoviesHash || showsHash != lastShowsHash else { return }

        lastMoviesHash = moviesHash
        lastShowsHash = showsHash

        // Build all events
        cachedEvents = CalendarEventBuilder.allEvents(movies: movies, tvShows: tvShows)

        // Build date-indexed dictionary for O(1) lookup
        var byDate: [DateComponents: [CalendarEvent]] = [:]
        for event in cachedEvents {
            let components = calendar.dateComponents([.year, .month, .day], from: event.date)
            byDate[components, default: []].append(event)
        }
        eventsByDate = byDate

        // Rebuild day data for current month
        rebuildDayDataCache()
    }

    /// Rebuild the pre-computed day data for the displayed month grid
    private func rebuildDayDataCache() {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            cachedDayData = []
            return
        }

        var dayData: [CalendarDayData] = []
        var currentDate = monthFirstWeek.start

        while currentDate < monthLastWeek.end {
            let isCurrentMonth = calendar.isDate(currentDate, equalTo: displayedMonth, toGranularity: .month)
            let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
            let eventsForDate = (eventsByDate[components] ?? []).filter(releaseRadar.isEnabled(for:))
            let movieCount = eventsForDate.filter { $0.isMovie }.count
            let tvShowCount = eventsForDate.filter { $0.isTVShow }.count

            dayData.append(CalendarDayData(
                id: currentDate,
                date: currentDate,
                isCurrentMonth: isCurrentMonth,
                movieCount: movieCount,
                tvShowCount: tvShowCount
            ))

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        cachedDayData = dayData
        lastDisplayedMonth = displayedMonth
    }

    // MARK: - iOS Calendar Components

    #if !os(tvOS)
    private var calendarHeader: some View {
        HStack {
            Button {
                withAnimation {
                    goToPreviousMonth()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthTitle)
                .font(AppTypography.title3(.bold))
                .foregroundColor(ColorPalette.textPrimaryDark)

            Spacer()

            Button {
                withAnimation {
                    goToNextMonth()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ColorPalette.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    private var daysOfWeekHeader: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(AppTypography.caption1(.semibold))
                    .foregroundColor(ColorPalette.textMutedDark)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppSpacing.sm)
    }

    private var calendarGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: AppSpacing.xs) {
            ForEach(cachedDayData) { dayData in
                let isSelected = calendar.isDate(dayData.date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(dayData.date)

                CalendarDayCell(
                    date: dayData.date,
                    isCurrentMonth: dayData.isCurrentMonth,
                    isSelected: isSelected,
                    isToday: isToday,
                    movieCount: dayData.movieCount,
                    tvShowCount: dayData.tvShowCount
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedDate = dayData.date
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
    }

    private var calendarLegend: some View {
        HStack(spacing: AppSpacing.lg) {
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(ColorPalette.primary)
                    .frame(width: 8, height: 8)
                Text("Movies")
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }

            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(ColorPalette.secondary)
                    .frame(width: 8, height: 8)
                Text("TV Shows")
                    .font(AppTypography.caption1())
                    .foregroundColor(ColorPalette.textSecondaryDark)
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    private var selectedDateSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Date Header
            Text(selectedDateFormatted)
                .font(AppTypography.headline(.bold))
                .foregroundColor(ColorPalette.textPrimaryDark)
                .padding(.horizontal, AppSpacing.md)

            if eventsForSelectedDate.isEmpty {
                // Empty State
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundColor(ColorPalette.textMutedDark)

                    Text("No releases scheduled")
                        .font(AppTypography.subheadline())
                        .foregroundColor(ColorPalette.textSecondaryDark)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else {
                // Events List
                LazyVStack(spacing: AppSpacing.sm) {
                    ForEach(eventsForSelectedDate) { event in
                        CalendarEventCard(
                            event: event,
                            isFollowed: releaseRadar.isFollowing(event: event)
                        ) {
                            navigateToDetail(for: event)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.md)
            }
        }
    }
    #endif

    // MARK: - Helper Methods

    private func goToPreviousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func goToNextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func navigateToDetail(for event: CalendarEvent) {
        switch event.source {
        case .movie(let movie):
            navigationPath.append(movie)
        case .tvShow(let show):
            navigationPath.append(show)
        }
    }

    private func refreshData() async {
        await libraryState.loadAll(forceRefresh: true)

        // Update widget data with fresh library data
        syncWidgetData()
    }

    private func toggleReleaseRadarFilter(_ filter: ReleaseRadarEventFilter) {
        releaseRadar.toggleFilter(filter)
    }

    private func syncWidgetData() {
        let hasServers = ConfigurationManager.shared.isRadarrConfigured || ConfigurationManager.shared.isSonarrConfigured
        WidgetDataService.shared.updateWidgetData(
            movies: libraryState.movies,
            tvShows: libraryState.tvShows,
            isConfigured: hasServers,
            forceReload: true
        )
    }

    private func releaseRadarSort(lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        let lhsFollowed = releaseRadar.isFollowing(event: lhs)
        let rhsFollowed = releaseRadar.isFollowing(event: rhs)

        if lhsFollowed != rhsFollowed {
            return lhsFollowed
        }

        if lhs.date != rhs.date {
            return lhs.date < rhs.date
        }

        return lhs.title < rhs.title
    }
}

#Preview {
    CalendarView()
        .preferredColorScheme(.dark)
}
