//
//  FlowTests.swift
//  MTR Lift Guide UITests
//
//  End-to-end walk of the tab-based flow on the simulator, saving screenshots
//  to /tmp/mtr-shots for design review.
//

import XCTest

final class FlowTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func snap(_ name: String) throws {
        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "/tmp/mtr-shots/\(name).png")
        try? FileManager.default.createDirectory(atPath: "/tmp/mtr-shots",
                                                withIntermediateDirectories: true)
        try shot.pngRepresentation.write(to: url)
    }

    /// Dismisses iOS permission alerts (location / camera) so the walkthrough stays clean.
    private func dismissAlerts(_ app: XCUIApplication) {
        for _ in 0..<3 {
            let button = app.alerts.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Allow' OR label CONTAINS '允許' OR label CONTAINS '好'")
            ).firstMatch
            if button.waitForExistence(timeout: 2) {
                button.tap()
            } else {
                break
            }
        }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 30) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp(velocity: .fast)
            swipes += 1
        }
    }

    func testHomeToAREndToEnd() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            let allow = alert.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'Allow' OR label CONTAINS '允許'")
            ).firstMatch
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()
        dismissAlerts(app)

        // Home — switch language and back, then open the station picker.
        let toggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Switch to Chinese' OR label CONTAINS '切換至英文'")
        ).firstMatch
        if toggle.waitForExistence(timeout: 6) {
            try snap("00-home")
            toggle.tap()
            try snap("00b-home-en-or-zh")
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Switch to Chinese' OR label CONTAINS '切換至英文'")
            ).firstMatch.tap()
        }

        // Fresh install shows the empty-state card instead of the current-station card.
        let changeStation = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Change station' OR label CONTAINS '更改車站'")
        ).firstMatch
        if changeStation.waitForExistence(timeout: 4) {
            changeStation.tap()
        } else {
            let choose = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Choose station' OR label CONTAINS '選擇車站'")
            ).firstMatch
            XCTAssertTrue(choose.waitForExistence(timeout: 4), "No station entry point on Home")
            choose.tap()
        }

        // Station list — pick Whampoa (scroll if needed)
        let stationRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Whampoa'")
        ).firstMatch
        scrollTo(stationRow, in: app)
        XCTAssertTrue(stationRow.waitForExistence(timeout: 5), "Whampoa row not found")
        try snap("01-station-list")
        stationRow.tap()

        // Exits — pick Exit A
        let exitRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Exit A'")
        ).firstMatch
        XCTAssertTrue(exitRow.waitForExistence(timeout: 5), "Exit A row not found")
        try snap("02-exits")
        exitRow.tap()

        // Accessibility — lift route
        let liftRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Lift all the way' OR label CONTAINS '全程電梯'")
        ).firstMatch
        XCTAssertTrue(liftRow.waitForExistence(timeout: 5), "Lift option not found")
        try snap("03-accessibility")
        liftRow.tap()

        // Route — timeline
        let startAR = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Start AR guidance' OR label CONTAINS 'AR 實景導航'")
        ).firstMatch
        XCTAssertTrue(startAR.waitForExistence(timeout: 5), "AR button not found")
        try snap("04-route")

        // AR guidance (camera unavailable on simulator)
        startAR.tap()
        let next = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Next waypoint' OR label CONTAINS '下一指示'")
        ).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8), "Guidance screen did not load")
        dismissAlerts(app)
        try snap("05-guidance")

        // Walk the waypoints (Whampoa → A lift route has 4) and confirm arrival.
        for _ in 0..<3 {
            let current = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Next waypoint' OR label CONTAINS '下一指示'")
            ).firstMatch
            if current.exists { current.tap() }
            usleep(400_000)
        }
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Arrived' OR label CONTAINS '抵達出口'")
        ).firstMatch.exists, "Arrival state not reached")
        try snap("06-arrived")

        // Tab bar — jump to Recents via the tab button
        let recentsTab = app.buttons.matching(
            NSPredicate(format: "label == 'Recent' OR label == '最近'")
        ).firstMatch
        if recentsTab.exists {
            recentsTab.tap()
            try snap("07-recents")
        }
    }

    /// Checks that the voice guidance language picker lives under More and can switch
    /// between Cantonese / Mandarin / English.
    func testMoreVoiceLanguagePicker() throws {
        let app = XCUIApplication()
        app.launch()

        let moreTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'More' OR label CONTAINS '更多'")
        ).firstMatch
        XCTAssertTrue(moreTab.waitForExistence(timeout: 6), "More tab missing")
        moreTab.tap()

        let voiceRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '語音導航語言' OR label CONTAINS 'Voice guidance'")
        ).firstMatch
        XCTAssertTrue(voiceRow.waitForExistence(timeout: 6), "Voice language picker missing")
        try snap("10-more-voice")

        voiceRow.tap()
        let mandarin = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Mandarin' OR label CONTAINS '普通話'")
        ).firstMatch
        XCTAssertTrue(mandarin.waitForExistence(timeout: 5),
                      "Language options missing (menu did not open)")
        mandarin.tap()
        try snap("11-more-voice-mandarin")

        let updated = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Mandarin' OR label CONTAINS '普通話'")
        ).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5),
                      "Voice language did not switch to Mandarin")
    }

    /// Checks that the station search field sits at the top of the screen and is
    /// not hidden behind the floating tab bar.
    func testStationsTabSearchPlacement() throws {
        let app = XCUIApplication()
        app.launch()

        let stationsTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Stations' OR label CONTAINS '車站'")
        ).firstMatch
        XCTAssertTrue(stationsTab.waitForExistence(timeout: 6), "Stations tab missing")
        stationsTab.tap()

        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 6), "Search field missing on Stations tab")

        let screen = app.windows.firstMatch.frame
        let frame = field.frame
        XCTAssertLessThan(frame.minY, screen.height * 0.35,
                          "Search field is not at the top (y=\(frame.minY))")
        XCTAssertGreaterThan(frame.maxX, screen.width * 0.5, "Search field is too narrow")

        try snap("08-stations-search")

        field.tap()
        field.typeText("WHA")
        try snap("09-stations-search-typed")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Whampoa' OR label CONTAINS '黃埔'")
        ).firstMatch.waitForExistence(timeout: 5), "Search results not filtered")
    }
}
