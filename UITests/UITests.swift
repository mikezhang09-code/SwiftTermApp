//
//  UITests.swift
//  UITests
//
//  Created by Miguel de Icaza on 3/10/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import XCTest

class UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAddHost() throws {

    }

    func testLocalTerminalOpens() throws {
        let app = XCUIApplication()
        app.launch()

        let dismiss = app.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }

        // On iPad the app is a split view; the Home sidebar (with Local Terminal) may
        // launch collapsed, so reveal it by tapping the sidebar toggle if needed.
        let link = app.staticTexts["Local Terminal"].firstMatch
        if !link.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (link.waitForExistence(timeout: 10), "Local Terminal entry not found on Home")
        link.tap()
        sleep (3)

        // Type commands and screenshot shortly after. This checks both that the prompt
        // returns promptly (was ~3s via the old failsafe) and that command output prints
        // before the next prompt (a single reader keeps them ordered).
        app.typeText ("uname -a\n")
        usleep (500_000)
        app.typeText ("echo ORDER-CHECK\n")
        usleep (500_000)

        let attachment = XCTAttachment (screenshot: app.screenshot ())
        attachment.lifetime = .keepAlways
        add (attachment)

        // Dump the view hierarchy so we can see whether the terminal view exists
        print ("HIERARCHY-BEGIN")
        print (app.debugDescription)
        print ("HIERARCHY-END")
    }

    //let password = try String (contentsOf: URL (fileURLWithPath: "/Users/miguel/password"))

    func testAddHostLoginPassword() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()
        
        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
                
        let tablesQuery = app.tables
        tablesQuery/*@START_MENU_TOKEN@*/.buttons["Hosts"]/*[[".cells[\"Hosts\"].buttons[\"Hosts\"]",".buttons[\"Hosts\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        tablesQuery.cells["Add, Add Host"].children(matching: .other).element(boundBy: 0).children(matching: .other).element.tap()
        let name = tablesQuery/*@START_MENU_TOKEN@*/.textFields["name"]/*[[".cells[\"Alias, name\"].textFields[\"name\"]",".textFields[\"name\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/
        name.tap()
        name.typeText("dbserver")
        
        tablesQuery/*@START_MENU_TOKEN@*/.textFields["192.168.1.100"]/*[[".cells[\"Host, 192.168.1.100\"].textFields[\"192.168.1.100\"]",".textFields[\"192.168.1.100\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        tablesQuery.textFields["192.168.1.100"].typeText("172.25.2.1")
        tablesQuery/*@START_MENU_TOKEN@*/.textFields["user"]/*[[".cells[\"Username, user\"].textFields[\"user\"]",".textFields[\"user\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        tablesQuery.textFields["user"].typeText("sa")
        tablesQuery/*@START_MENU_TOKEN@*/.secureTextFields["•••••••"]/*[[".cells[\"Password, •••••••, Show\"].secureTextFields[\"•••••••\"]",".secureTextFields[\"•••••••\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        tablesQuery/*@START_MENU_TOKEN@*/.secureTextFields["•••••••"]/*[[".cells[\"Password, •••••••, Show\"].secureTextFields[\"•••••••\"]",".secureTextFields[\"•••••••\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.typeText("pass")
        let port: XCUIElement = tablesQuery.textFields ["22"]
        
        port.doubleTap()
        port.typeText ("2201")
        
        app.navigationBars["_TtGC7SwiftUI19UIHosting"].buttons["Save"].tap()
    }

    func testLogin () {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()
        
        app.tables.buttons["dbserver, 172.25.2.1"].tap()
        
        // Needed when we do not trust yet
        //app.buttons["Yes"].tap()
        
        app.typeText("mc\ncd /usr\n\tcd /usr/bin\n")
        print ("Here")
    }
    // Reproduces: selecting the "Live" background tab freezes the UI.
    // While this test sleeps, the app process can be sampled externally to
    // capture where the main thread is stuck.
    func testLiveBackgroundFreeze() throws {
        let app = XCUIApplication()
        app.launch()

        // Dismiss the first-run onboarding if it is showing
        let cont = app.buttons["Continue"].firstMatch
        if cont.waitForExistence(timeout: 3) {
            cont.tap()
        }

        var settingsButton = app.buttons["Settings"].firstMatch
        if !settingsButton.waitForExistence(timeout: 5) {
            // iPad: the sidebar starts collapsed, open it first
            let toggle = app.navigationBars.buttons.firstMatch
            if toggle.exists {
                toggle.tap()
            }
            settingsButton = app.buttons["Settings"].firstMatch
            if !settingsButton.waitForExistence(timeout: 5) {
                print("HIERARCHY-HOME: \(app.debugDescription)")
                XCTFail("No Settings entry found")
            }
        }
        settingsButton.tap()

        var live = app.buttons["Live"].firstMatch
        if !live.waitForExistence(timeout: 8) {
            live = app.segmentedControls.buttons["Live"].firstMatch
            if !live.exists {
                print("HIERARCHY-SETTINGS: \(app.debugDescription)")
                XCTFail("No Live segment found")
            }
        }
        live.tap()

        // Keep the app in this state so it can be sampled
        sleep(10)

        // If the main thread froze, this will fail
        let solid = app.buttons["Solid"].firstMatch
        XCTAssertTrue(solid.isHittable, "UI is not hittable after enabling Live previews")

        // Cycle the previews in and out: destroying the preview views used to
        // crash with a use-after-free in MetalHostView.deinit
        for _ in 0..<3 {
            solid.tap()
            sleep(2)
            app.buttons["Live"].firstMatch.tap()
            sleep(2)
        }
        solid.tap()
        sleep(3)
        XCTAssertTrue(app.buttons["Live"].firstMatch.isHittable, "UI died after cycling Live previews")
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
