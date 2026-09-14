//
//  Media_ManagerUITests.swift
//  Media ManagerUITests
//
//

import XCTest
import UIKit

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
            let row = app.tables.cells.containing(.staticText, identifier: tab).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = tab
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }

        let radarr = app.staticTexts["Radarr Server"]
        XCTAssertTrue(radarr.waitForExistence(timeout: 5))
        radarr.tap()
        XCTAssertTrue(app.navigationBars["Radarr Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields.firstMatch.exists)
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
