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

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
