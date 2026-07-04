//
//  BigImmichUITests.swift
//  BigImmichUITests
//
//  Created by Maciej Płoński on 09/10/2025.
//

import XCTest

final class BigImmichUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesToFirstScreen() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "App did not reach the foreground after launch"
        )
        XCTAssertTrue(
            app.staticTexts.firstMatch.waitForExistence(timeout: 20),
            "App launched but rendered no text on its first screen"
        )
    }

    @MainActor
    func testLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
