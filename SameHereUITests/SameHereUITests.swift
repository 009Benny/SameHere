//
//  SameHereUITests.swift
//  SameHereUITests
//
//  Created by Benny Reyes on 03/08/26.
//

import XCTest

final class SameHereUITests: XCTestCase {

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

        // Whatever the auth state (signed out, guest, signed in), the app must
        // come up and show something instead of crashing or sitting on a blank screen.
        XCTAssertEqual(app.state, .runningForeground)
        let anyContent = app.buttons.firstMatch.waitForExistence(timeout: 15)
            || app.staticTexts.firstMatch.waitForExistence(timeout: 1)
        XCTAssertTrue(anyContent, "The app launched but showed no UI.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
