//
//  bikeUITests.swift
//  bikeUITests
//
//  Created by chenchi on 2026/7/19.
//

import XCTest

final class bikeUITests: XCTestCase {

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
    func testPrimaryNavigationAndAboutPage() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.tabBars.buttons["骑行"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["历史"].exists)
        XCTAssertTrue(app.tabBars.buttons["设置"].exists)

        app.tabBars.buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
        app.buttons["关于骑行"].tap()

        XCTAssertTrue(app.navigationBars["关于"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["骑行"].exists)
        XCTAssertTrue(app.staticTexts["记录每一次骑行"].exists)
        XCTAssertTrue(app.staticTexts["骑行记录仅保存在本机"].exists)
        XCTAssertTrue(app.staticTexts["定位用于记录骑行轨迹、距离和速度"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
