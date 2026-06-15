//
//  vibekubeUITests.swift
//  vibekubeUITests
//
//  Created by art on 27.05.2026.
//

import AppKit
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
        let attachment = XCTAttachment(screenshot: yamlText.screenshot())
        attachment.name = "Rendered YAML Text View"
        attachment.lifetime = .keepAlways
        add(attachment)

        let yamlValue = try XCTUnwrap(yamlText.value as? String)
        XCTAssertTrue(yamlValue.contains("apiVersion: v1"))
        XCTAssertTrue(yamlValue.contains("kind: Pod"))
        XCTAssertTrue(yamlValue.contains("name: web-0"))
        XCTAssertTrue(yamlValue.contains("containers:"))
        try assertYAMLContentAreaHasPaintedGlyphs(in: yamlText)
    }

    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["VIBEKUBE_USE_PREVIEW_CLUSTERS"] = "1"
        app.launchEnvironment["VIBEKUBE_USE_PREVIEW_DATA"] = "1"
        return app
    }

    private func assertYAMLContentAreaHasPaintedGlyphs(
        in element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let screenshot = element.screenshot()
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(data: screenshot.pngRepresentation),
            "Could not decode YAML text screenshot.",
            file: file,
            line: line
        )
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        XCTAssertGreaterThan(width, 120, file: file, line: line)
        XCTAssertGreaterThan(height, 80, file: file, line: line)

        let startX = min(max(60, width / 12), max(0, width - 1))
        let endX = max(startX, width - 24)
        var paintedPixelCount = 0

        stride(from: 6, to: max(6, height - 6), by: 3).forEach { y in
            stride(from: startX, to: endX, by: 3).forEach { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    return
                }

                let red = color.redComponent * 255
                let green = color.greenComponent * 255
                let blue = color.blueComponent * 255
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                if luminance > 55 {
                    paintedPixelCount += 1
                }
            }
        }

        XCTAssertGreaterThan(
            paintedPixelCount,
            80,
            "YAML text view accessibility had content, but the visible content area looked blank.",
            file: file,
            line: line
        )
    }
}
