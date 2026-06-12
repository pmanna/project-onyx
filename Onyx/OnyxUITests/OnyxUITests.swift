//
//  OnyxUITests.swift
//  OnyxUITests
//
//  Created by Errol Brandt on 6/6/2026.
//

import XCTest

final class OnyxUITests: XCTestCase {

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
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    /// Downloads the catalog model and asserts the progress meter advances
    /// regularly — the percent label must never sit unchanged for more than
    /// 15 seconds while the download is in flight.
    ///
    /// Requires the model to NOT already be installed (delete the app's
    /// Models directory first, or uninstall in the UI).
    @MainActor
    func testDownloadProgressMovesRegularly() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Models"].tap()

        let download = app.buttons["Download"].firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10),
                      "Download button not found — is the model already installed?")
        download.tap()

        // The percent label re-renders 4×/second, so element queries go stale
        // between resolution and read. Parse one atomic accessibility snapshot
        // (debugDescription) per poll instead of querying live elements.
        var lastPercent = -1
        var lastChange = Date()
        var maxGap: TimeInterval = 0
        var finished = false
        let deadline = Date().addingTimeInterval(360)

        while Date() < deadline {
            let tree = app.debugDescription
            // "Uninstall" only renders once the model is installed — download done.
            if tree.contains("Uninstall") {
                finished = true
                break
            }
            let percent = tree.matches(of: /(\d+)%/).compactMap { Int($0.1) }.first ?? lastPercent
            let now = Date()
            if percent != lastPercent {
                maxGap = max(maxGap, now.timeIntervalSince(lastChange))
                lastPercent = percent
                lastChange = now
            } else if now.timeIntervalSince(lastChange) > 15 {
                XCTFail("Progress meter frozen at \(lastPercent)% for more than 15 s")
                return
            }
            Thread.sleep(forTimeInterval: 1.0)
        }

        XCTAssertTrue(finished,
                      "Download did not complete within 6 minutes (last seen: \(lastPercent)%)")
        XCTAssertLessThanOrEqual(maxGap, 15, "Largest gap between progress updates was \(maxGap) s")
    }
}
