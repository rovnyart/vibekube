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
    func testPreviewPodManifestRendersYAMLText() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["kind-vibekube-dev"].exists)
        XCTAssertTrue(app.buttons["toolbar.refresh"].exists)

        app.buttons["toolbar.connection"].click()

        let podsItem = app.buttons["resource.nav.pods"]
        XCTAssertTrue(podsItem.waitForExistence(timeout: 5))
        podsItem.click()

        let podName = app.staticTexts["web-0"].firstMatch
        XCTAssertTrue(podName.waitForExistence(timeout: 5))
        podName.click()

        let yamlText = app.textViews["resource.detail.yaml.text"]
        XCTAssertTrue(yamlText.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(yamlText.frame.width, 240)
        XCTAssertGreaterThan(yamlText.frame.height, 120)

        let yamlValue = try XCTUnwrap(yamlText.value as? String)
        XCTAssertTrue(yamlValue.contains("apiVersion: v1"))
        XCTAssertTrue(yamlValue.contains("kind: Pod"))
        XCTAssertTrue(yamlValue.contains("name: web-0"))
        XCTAssertTrue(yamlValue.contains("containers:"))
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
        app.launchEnvironment["VIBEKUBE_USE_PREVIEW_DATA"] = "1"
        return app
    }
}
