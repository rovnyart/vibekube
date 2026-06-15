//
//  vibekubeUITests.swift
//  vibekubeUITests
//
//  Created by art on 27.05.2026.
//

import XCTest

final class vibekubeUITests: XCTestCase {

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
    func testShellLaunches() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["kind-vibekube-dev"].exists)
        XCTAssertTrue(app.buttons["toolbar.refresh"].exists)

        let podsItem = app.buttons["resource.nav.pods"]
        XCTAssertTrue(podsItem.waitForExistence(timeout: 5))
        podsItem.click()
        XCTAssertTrue(app.staticTexts["resource.placeholder.pods"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = configuredApp()
            app.launch()
        }
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["VIBEKUBE_USE_PREVIEW_CLUSTERS"] = "1"
        return app
    }
}
