//
//  Media_ManagerUITests.swift
//  Media ManagerUITests
//
//

import XCTest
import UIKit
#if os(iOS) && MEDIA_APP_INTENTS_TESTING
import AppIntentsTesting
#endif

final class Media_ManagerUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    #if os(iOS)
    #if MEDIA_APP_INTENTS_TESTING
    @available(iOS 27.0, *)
    @MainActor
    func testSystemMovieEntityQuery() async throws {
        let app = XCUIApplication()
        app.launchArguments = ["--media-intelligence-fixtures"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Movies"].waitForExistence(timeout: 15))
        let definitions = IntentDefinitions(bundleIdentifier: "com.myandroidtv.MediaManager")
        let entities = try await definitions.entities["MovieSearchResultEntity"].entities(identifiers: [800, 999])
        XCTAssertEqual(entities.count, 1)
        XCTAssertEqual(entities.first?.identifier.instanceIdentifier, "800")
        app.buttons["openLibraryAssistant"].tap()
        let title = app.buttons["The Lunar Garden (2026)"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        XCTAssertTrue(app.staticTexts["The Lunar Garden"].waitForExistence(timeout: 5))
        let annotations = try await definitions.entities["MovieSearchResultEntity"].viewAnnotations()
        XCTAssertTrue(annotations.contains { $0.entity.identifier.instanceIdentifier == "800" }, "Movie details should expose the catalog entity")
        var indexed = false
        for _ in 0..<15 {
            let results = try await definitions.entities["MovieSearchResultEntity"].spotlightQuery("Lunar")
            if results.contains(where: { $0.identifier.instanceIdentifier == "800" }) { indexed = true; break }
            try await Task.sleep(for: .seconds(1))
        }
        XCTAssertTrue(indexed, "Loaded movie should be discoverable through Spotlight")
    }

    #endif

    @MainActor
    func testLibraryAssistantAvailabilityAndFallback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-radarrURL", "", "-sonarrURL", "", "-sabnzbURL", "", "-unraidURL", "", "-iCloudSyncEnabled", "NO"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Movies"].waitForExistence(timeout: 15))
        let assistant = app.buttons["openLibraryAssistant"]
        if #available(iOS 27.0, *) {
            XCTAssertTrue(assistant.waitForExistence(timeout: 10))
            assistant.tap()
            let query = app.textFields["libraryAssistantQuery"]
            let multilineQuery = app.textViews["libraryAssistantQuery"]
            XCTAssertTrue(query.waitForExistence(timeout: 5) || multilineQuery.exists)
            XCTAssertTrue(app.staticTexts["No matching movies"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["No matching TV shows"].exists)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "OS27 Library Assistant"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.buttons["Done"].tap()
        } else {
            XCTAssertFalse(assistant.exists)
        }
        app.tabBars.buttons["Movies"].tap()
        XCTAssertTrue(app.staticTexts["Radarr Not Configured"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testMainNavigationAndServerSettings() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "iPhone More navigation")
        let app = XCUIApplication()
        // Process-only defaults keep this navigation check independent of servers.
        app.launchArguments = ["-radarrURL", "", "-sonarrURL", "", "-sabnzbURL", "", "-unraidURL", ""]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Movies"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Configure TMDB in Settings. Your library and server data remain available here."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Couldn't Load Home"].exists)

        for (tab, content) in [("Movies", "Radarr Not Configured"), ("TV Shows", "Sonarr Not Configured")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.staticTexts[content].waitForExistence(timeout: 5))
        }
        app.tabBars.buttons["Discover"].tap()
        XCTAssertTrue(app.staticTexts["TMDB Not Configured"].waitForExistence(timeout: 5))

        for (tab, title) in [("Downloads", "Downloads"), ("Calendar", "Calendar"), ("Unraid", "Server"), ("Settings", "Settings")] {
            app.tabBars.buttons["More"].tap()
            let row = app.buttons.matching(identifier: "more.\(["Downloads": 4, "Calendar": 5, "Unraid": 6, "Settings": 7][tab]!)").firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = tab
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertEqual(app.navigationBars.count, 1)
            if tab != "Settings" { app.navigationBars.buttons["More"].tap() }
        }

        let radarr = app.staticTexts["Radarr Server"]
        XCTAssertTrue(radarr.waitForExistence(timeout: 5))
        radarr.tap()
        XCTAssertTrue(app.navigationBars["Radarr Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields.firstMatch.exists)
    }

    @MainActor
    func testSingleBackButtonAcrossSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-radarrURL", "", "-sonarrURL", "", "-sabnzbURL", "", "-unraidURL", "", "-iCloudSyncEnabled", "NO"]
        app.launch()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            let settings = app.staticTexts["Settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            settings.tap()
        } else {
            XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 15))
            app.tabBars.buttons["More"].tap()
            app.buttons["more.7"].tap()
        }
        for (row, title) in [("Radarr Server", "Radarr Settings"), ("Sonarr Server", "Sonarr Settings"), ("SabNZB Server", "SabNZB Settings"), ("Unraid Server", "Unraid Settings"), ("TMDB", "TMDB Settings"), ("Add Defaults & Presets", "Add Defaults")] {
            let link = app.staticTexts[row].firstMatch
            for _ in 0..<4 { if link.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(link.isHittable)
            link.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            let back = bar.buttons["Settings"]
            XCTAssertEqual(bar.buttons.matching(identifier: "Settings").count, 1)
            if !isPad { XCTAssertEqual(app.navigationBars.count, 1) }
            back.tap()
            XCTAssertTrue(app.staticTexts["Radarr Server"].waitForExistence(timeout: 5))
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Single navigation bar - Settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if !isPad {
            app.navigationBars.buttons["More"].tap()
            XCTAssertTrue(app.buttons["more.4"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testIPadSidebarNavigation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad sidebar navigation")
        let app = XCUIApplication()
        app.launchArguments = ["-radarrURL", "", "-sonarrURL", "", "-sabnzbURL", "", "-unraidURL", ""]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending content is unavailable"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Couldn't Load Home"].exists)
        for title in ["Downloads", "Calendar", "Settings"] {
            app.staticTexts[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "iPad " + title
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    #endif

    #if os(tvOS)
    @MainActor
    private func selectTVTab(_ name: String, in app: XCUIApplication) {
        let target = app.tabBars.buttons[name]
        for _ in 0..<14 {
            if app.tabBars.buttons.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }
            XCUIRemote.shared.press(.up)
        }
        let names = ["Home", "Discover", "Movies", "TV Shows", "Downloads", "Calendar", "Unraid", "Settings"]
        for _ in 0..<8 {
            if target.hasFocus { break }
            let current = names.firstIndex { app.tabBars.buttons[$0].hasFocus } ?? 0
            let destination = names.firstIndex(of: name) ?? 0
            XCUIRemote.shared.press(current < destination ? .right : .left)
        }
        XCTAssertTrue(target.hasFocus, "Could not focus \(name)")
        XCUIRemote.shared.press(.select)
    }

    @MainActor
    private func captureTVScreen(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTVPopulatedDesignAndAddOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--tv-design-fixtures"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        selectTVTab("Movies", in: app)
        XCTAssertTrue(app.staticTexts["The Last Observatory"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Browsing must not open a keyboard")
        captureTVScreen("TV design - Movie library", app: app)

        let search = app.buttons["Search Movies"]
        for _ in 0..<4 {
            if search.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(search.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.alerts["Search Movies"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)

        let addMovie = app.buttons["Add"]
        for _ in 0..<5 {
            if addMovie.hasFocus { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(addMovie.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Add Options"].waitForExistence(timeout: 5))
        captureTVScreen("TV design - Add movie", app: app)
        let options = app.buttons["Add Options"]
        for _ in 0..<6 {
            if options.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(options.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Quality Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HD • 1080p"].waitForExistence(timeout: 10))
        captureTVScreen("TV design - Add options", app: app)
        let quality = app.buttons["Quality Profile"]
        for _ in 0..<5 {
            if quality.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(quality.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Ultra HD • 4K"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["HD • 1080p"].exists)
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        selectTVTab("TV Shows", in: app)
        XCTAssertTrue(app.staticTexts["Beyond the Horizon"].waitForExistence(timeout: 5))
        captureTVScreen("TV design - Show library", app: app)
        selectTVTab("Downloads", in: app)
        XCTAssertTrue(app.staticTexts["The Last Observatory (2026) — 2160p"].waitForExistence(timeout: 10))
        captureTVScreen("TV design - Downloads", app: app)
        app.open(URL(string: "mediamanager://movie/1")!)
        XCTAssertTrue(app.staticTexts["The Last Observatory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "An unexpected discovery")).firstMatch.waitForExistence(timeout: 5))
        captureTVScreen("TV design - Movie details", app: app)
        let editMovie = app.buttons["tvEditDetails"]
        for _ in 0..<12 {
            if editMovie.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        for _ in 0..<3 {
            if editMovie.hasFocus { break }
            XCUIRemote.shared.press(.left)
        }
        captureTVScreen("TV design - Detail remote focus", app: app)
        XCTAssertTrue(editMovie.hasFocus, app.debugDescription)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.navigationBars["Edit Movie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HD • 1080p"].waitForExistence(timeout: 5))
        captureTVScreen("TV design - Edit movie", app: app)
        XCUIRemote.shared.press(.menu)
        XCUIRemote.shared.press(.menu)
        app.open(URL(string: "mediamanager://tvshow/1")!)
        XCTAssertTrue(app.staticTexts["Beyond the Horizon"].waitForExistence(timeout: 5))
        captureTVScreen("TV design - Show details", app: app)
    }

    @MainActor
    func testTVRemoteNavigationAndSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-radarrURL", "", "-sonarrURL", "", "-sabnzbURL", "", "-unraidURL", ""]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 15))
        for (tab, content) in [("Discover", "TMDB Not Configured"), ("Movies", "Radarr Not Configured"), ("TV Shows", "Sonarr Not Configured"), ("Downloads", "SabNZB Not Configured"), ("Calendar", "No releases scheduled"), ("Unraid", "Unraid Not Configured"), ("Settings", "Radarr")] {
            let tabButton = app.tabBars.buttons[tab]
            for _ in 0..<12 {
                if app.tabBars.buttons.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }
                XCUIRemote.shared.press(.up)
            }
            for _ in 0..<8 {
                if tabButton.hasFocus { break }
                XCUIRemote.shared.press(.right)
            }
            XCTAssertTrue(tabButton.hasFocus, "Remote could not focus \(tab)")
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(app.staticTexts[content].waitForExistence(timeout: 10), "Missing content for \(tab)")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Apple TV " + tab
            attachment.lifetime = .keepAlways
            add(attachment)
            if tab == "Calendar" {
                let nextMonth = app.buttons["Next month"]
                for _ in 0..<4 {
                    if nextMonth.hasFocus { break }
                    XCUIRemote.shared.press(.right)
                }
                XCTAssertTrue(nextMonth.hasFocus)
                let calendar = Calendar.current
                var month = Date()
                for _ in 0..<12 {
                    if calendar.range(of: .weekOfMonth, in: .month, for: month)?.count == 6 { break }
                    month = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: month))
                    XCUIRemote.shared.press(.select)
                }
                // Traverse to the bottom row; focus must scroll it into view.
                for _ in 0..<8 { XCUIRemote.shared.press(.down) }
                let focusedDay = app.buttons.allElementsBoundByIndex.first { $0.hasFocus }
                XCTAssertNotNil(focusedDay)
                XCTAssertTrue(focusedDay?.isHittable == true)
                let sixWeeks = XCTAttachment(screenshot: app.screenshot())
                sixWeeks.name = "Apple TV six-week calendar"
                sixWeeks.lifetime = .keepAlways
                add(sixWeeks)
            }
        }
        let radarr = app.buttons.containing(.staticText, identifier: "Radarr").firstMatch
        for _ in 0..<4 {
            if radarr.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(radarr.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Server URL"].waitForExistence(timeout: 5))
        let serverURL = app.buttons.containing(.staticText, identifier: "Server URL").firstMatch
        for _ in 0..<4 {
            if serverURL.hasFocus { break }
            XCUIRemote.shared.press(.down)
        }
        XCTAssertTrue(serverURL.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.alerts["Server URL"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.staticTexts["Server URL"].exists)
    }
    #endif

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

#if os(iOS)
extension Media_ManagerUITests {
    @MainActor
    func testUnreachableUnraidIsHiddenFromDashboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-dashboard", "--unraid-offline"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trending content is unavailable"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertFalse(app.staticTexts["Server Health"].exists)
        XCTAssertFalse(app.staticTexts["Server unavailable"].exists)
        XCTAssertFalse(app.staticTexts["Tap to retry"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Dashboard away from LAN"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-dashboard"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Server Health"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["TEST TOWER"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnraidStorageWarnings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-storage-warnings"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TEST TOWER"].waitForExistence(timeout: 15))
        let cache = app.staticTexts["Cache storage"]
        for _ in 0..<4 { if cache.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(cache.exists)
        let critical = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Critically low space")).firstMatch
        XCTAssertTrue(critical.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "16.76 GB free")).firstMatch.exists)
        let unavailable = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Filesystem usage unavailable")).firstMatch
        XCTAssertTrue(unavailable.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unraid storage and cache warnings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.swipeUp()
        let inventory = XCTAttachment(screenshot: app.screenshot())
        inventory.name = "Unraid filesystem inventory"
        inventory.lifetime = .keepAlways
        add(inventory)
    }

    @MainActor
    func testUnraidPartialSectionsAndContainerDiagnostics() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-partial"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TEST TOWER"].waitForExistence(timeout: 15))
        let details = app.buttons["unraid.details.server:plex"]
        for _ in 0..<6 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "VM service unavailable")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Status unavailable"].exists)
        XCTAssertFalse(app.staticTexts["0/0 running"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Unraid partial sections"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        details.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Plex service started successfully")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "CPU: 12")).firstMatch.waitForExistence(timeout: 10))
        let diagnostics = XCTAttachment(screenshot: app.screenshot())
        diagnostics.name = "Unraid container diagnostics"
        diagnostics.lifetime = .keepAlways
        add(diagnostics)
        app.buttons["Done"].tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnraidHardwareFailureKeepsHealthySectionsDuringRefresh() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-hardware-failure"]
        app.launch()
        let details = app.buttons["unraid.details.server:plex"]
        XCTAssertTrue(details.waitForExistence(timeout: 15))
        for _ in 0..<6 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable)
        app.buttons["unraid.refresh"].tap()
        // The fixture delays the failed hardware resolver for two seconds.
        XCTAssertTrue(details.isHittable, "Refreshing unavailable hardware must retain healthy sections")
        XCTAssertFalse(app.staticTexts["Connecting to server..."].exists)
    }

    @MainActor
    func testUnraidViewerControlsAndLongCommandBusyState() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--unraid-integration-fixtures", "--unraid-viewer"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TEST TOWER"].waitForExistence(timeout: 15))
        var restart = app.buttons["unraid.restart.server:plex"]
        for _ in 0..<6 { if restart.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(restart.exists)
        XCTAssertFalse(restart.isEnabled)
        app.terminate()
        app.launchArguments = ["--unraid-integration-fixtures"]
        app.launch()
        XCTAssertTrue(app.staticTexts["TEST TOWER"].waitForExistence(timeout: 15))
        restart = app.buttons["unraid.restart.server:plex"]
        for _ in 0..<6 { if restart.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(restart.isEnabled)
        restart.tap()
        let busy = app.descendants(matching: .any)["unraid.busy.server:plex"]
        XCTAssertTrue(busy.waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 2.2)
        XCTAssertTrue(busy.exists, "Busy state must outlive the old fixed two-second timer")
        let finished = NSPredicate(format: "exists == false")
        expectation(for: finished, evaluatedWith: busy)
        waitForExpectations(timeout: 10)
    }
}
#endif
