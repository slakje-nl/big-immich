//
//  SlideshowJourneyUITests.swift
//  BigImmichUITests
//
//  End-to-end journey against the local mock Immich server (test/mock-immich).
//  Run it via `just e2e-snapshots`, which starts the mock server first.
//  It captures a screenshot of every important screen and attaches them to the
//  result bundle; the just recipe exports them into test/snapshots/.
//
//  The tvOS focus engine can't be scripted as precisely as touch, so the
//  navigation below is heuristic (press-and-settle). continueAfterFailure is
//  on so a mis-step still yields the remaining screenshots to eyeball.
//

import Foundation
import XCTest

final class SlideshowJourneyUITests: XCTestCase {
    private let mockURL = ProcessInfo.processInfo
        .environment["MOCK_IMMICH_URL"] ?? "http://127.0.0.1:8123"
    private let apiKey = "mock-api-key"

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testSlideshowJourney() {
        let app = XCUIApplication()

        // 1. First boot with no configuration -> welcome screen.
        app.launchArguments = ["-uiTestReset"]
        app.launch()
        XCTAssertTrue(
            app.staticTexts["Welcome to Big Immich!"].waitForExistence(timeout: 20),
            "expected the welcome screen on first boot"
        )
        snapshot(app, "01-first-boot")

        // 2. Settings before any credentials are filled in.
        openSettingsTab()
        snapshot(app, "02-settings-empty")

        // 3. Type the mock-server credentials into the Settings form, exactly as
        //    a user would, and wait for the connection test to pass.
        typeCredential(mockURL, into: app.textFields["immichURLField"])
        typeCredential(apiKey, into: app.secureTextFields["apiKeyField"])
        XCTAssertTrue(
            app.staticTexts["Connection to Immich works!"].waitForExistence(timeout: 20),
            "expected a working connection to the mock server"
        )
        snapshot(app, "03-settings-configured")

        // 4. Albums grid.
        openAlbumsTab()
        XCTAssertTrue(
            app.staticTexts["Vacation"].waitForExistence(timeout: 20),
            "expected the mock albums to load"
        )
        snapshot(app, "04-albums")

        // 5. Album details.
        openFirstAlbum()
        XCTAssertTrue(
            app.buttons["startSlideshowButton"].waitForExistence(timeout: 20),
            "expected the album details screen"
        )
        snapshot(app, "05-album-details")

        // 6. Album assets grid.
        selectButton("viewAssetsButton")
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "06-album-assets")

        // 7. Slideshow: back to details, then start it and let an image load.
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 1)
        selectButton("startSlideshowButton")
        Thread.sleep(forTimeInterval: 4)
        snapshot(app, "07-slideshow")

        // 8. Paused slideshow (overlay with counter + date/location).
        XCUIRemote.shared.press(.playPause)
        Thread.sleep(forTimeInterval: 2)
        snapshot(app, "08-slideshow-paused")
    }

    // MARK: - Helpers

    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Moves focus downward onto the given field (the tvOS focus engine only
    /// exposes directional moves), presses Select to enter text-entry mode
    /// (on tvOS a highlighted field still lacks *keyboard* focus until then),
    /// types via the emulated hardware keyboard, and dismisses the keyboard
    /// with Menu, which keeps the entered text.
    private func typeCredential(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10), "text field not found")

        var focused = field.hasFocus
        for _ in 0 ..< 12 where !focused {
            XCUIRemote.shared.press(.down)
            Thread.sleep(forTimeInterval: 0.3)
            focused = field.hasFocus
        }
        XCTAssertTrue(focused, "could not focus the text field")

        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        XCUIApplication().typeText(text)
        Thread.sleep(forTimeInterval: 0.5)
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func press(_ button: XCUIRemote.Button, times: Int) {
        for _ in 0 ..< times {
            XCUIRemote.shared.press(button)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    /// The tab bar is at the top; Settings is the right-most segment.
    private func openSettingsTab() {
        press(.up, times: 4)
        press(.right, times: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// Albums is the left-most segment.
    private func openAlbumsTab() {
        press(.up, times: 4)
        press(.left, times: 3)
        Thread.sleep(forTimeInterval: 0.5)
    }

    private func openFirstAlbum() {
        press(.down, times: 3)
        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func selectButton(_ identifier: String) {
        let button = XCUIApplication().buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "button not found")

        // Stacked buttons can sit above or below the current focus, so scan one
        // direction and then the other until the target button is focused.
        if !focus(button, pressing: .down) {
            _ = focus(button, pressing: .up)
        }
        XCTAssertTrue(button.hasFocus, "could not focus \(identifier)")

        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func focus(
        _ button: XCUIElement,
        pressing direction: XCUIRemote.Button
    ) -> Bool {
        for _ in 0 ..< 6 {
            if button.exists, button.hasFocus {
                return true
            }
            XCUIRemote.shared.press(direction)
            Thread.sleep(forTimeInterval: 0.3)
        }
        return button.exists && button.hasFocus
    }
}
