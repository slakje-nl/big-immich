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
        typeCredential(mockURL, fieldID: "immichURLField", secure: false, in: app)
        typeCredential(apiKey, fieldID: "apiKeyField", secure: true, in: app)
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

    /// Moves focus downward onto the field (the tvOS focus engine only exposes directional moves),
    /// presses Select to enter text-entry mode (a highlighted field still lacks *keyboard* focus
    /// until then), types via the emulated hardware keyboard, and dismisses the keyboard with Menu,
    /// which keeps the entered text.
    private func typeCredential(_ text: String, fieldID: String, secure: Bool, in app: XCUIApplication) {
        let field = secure ? app.secureTextFields[fieldID] : app.textFields[fieldID]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "text field not found")

        // The redesigned settings puts a category sidebar on the left and the fields in a detail
        // pane. Move Right off the sidebar into the pane (harmless if already there); entry lands on
        // whichever control is nearest, so scan down and then up to settle on the target field.
        if !field.hasFocus {
            XCUIRemote.shared.press(.right)
            Thread.sleep(forTimeInterval: 0.4)
        }
        if !focus(field, pressing: .down) {
            _ = focus(field, pressing: .up)
        }
        XCTAssertTrue(field.hasFocus, "could not focus the text field")

        XCUIRemote.shared.press(.select)
        Thread.sleep(forTimeInterval: 1.0)
        app.typeText(text)
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

    /// Settings is now a full-page screen, so leave it with the Menu button — once from the detail
    /// pane back to the sidebar, once more to exit to Albums.
    private func openAlbumsTab() {
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.6)
        XCUIRemote.shared.press(.menu)
        Thread.sleep(forTimeInterval: 0.8)
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
