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

    func testAiSettingsOpens() throws {
        let app = XCUIApplication()
        app.launch()

        let dismiss = app.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }

        // Reveal the sidebar if it launched collapsed (iPad split view)
        let link = app.staticTexts["AI"].firstMatch
        if !link.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (link.waitForExistence(timeout: 10), "AI entry not found on Home")
        link.tap()

        XCTAssertTrue (app.navigationBars["AI Providers"].waitForExistence(timeout: 5), "AI Providers screen did not open")

        // Add an Anthropic provider from the + menu and check the editor shows
        app.navigationBars["AI Providers"].buttons.firstMatch.tap()
        let anthropic = app.buttons["Anthropic"].firstMatch
        XCTAssertTrue (anthropic.waitForExistence(timeout: 5), "Add-provider menu did not open")
        anthropic.tap()

        XCTAssertTrue (app.textFields["Base URL"].waitForExistence(timeout: 5), "Provider editor did not open")
        XCTAssertTrue (app.secureTextFields["API key"].exists, "API key field missing")
        XCTAssertTrue (app.buttons["Test"].exists, "Test button missing")

        let attachment = XCTAttachment (screenshot: app.screenshot ())
        attachment.lifetime = .keepAlways
        add (attachment)

        app.buttons["Cancel"].tap()
    }

    /// Full Explain flow against the local mock AI server (scratchpad
    /// ssetest/mock_sse.py must be running on 127.0.0.1:8765 — ATS exempts
    /// loopback, so plain http works in the simulator).
    func testExplainEndToEnd() throws {
        let app = XCUIApplication()
        app.launch()

        let dismiss = app.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }

        // 1. Configure a mock OpenAI-compatible provider
        let aiLink = app.staticTexts["AI"].firstMatch
        if !aiLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (aiLink.waitForExistence(timeout: 10))
        aiLink.tap()
        XCTAssertTrue (app.navigationBars["AI Providers"].waitForExistence(timeout: 5))

        app.navigationBars["AI Providers"].buttons.firstMatch.tap()
        let compatible = app.buttons["OpenAI-compatible…"].firstMatch
        XCTAssertTrue (compatible.waitForExistence(timeout: 5))
        compatible.tap()

        let urlField = app.textFields["Base URL"]
        XCTAssertTrue (urlField.waitForExistence(timeout: 5))
        urlField.tap()
        let existing = (urlField.value as? String) ?? ""
        urlField.typeText (String (repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 5))
        urlField.typeText ("http://127.0.0.1:8765")

        let keyField = app.secureTextFields["API key"]
        keyField.tap()
        keyField.typeText ("mock-key\n")   // return dismisses the keyboard

        // Test loads the endpoint's real model list (filtered to chat models).
        // Scroll first: rows under the keyboard are virtualized out of the
        // accessibility tree in a Form.
        let testButton = app.buttons["Test"]
        var scrolls = 0
        while !testButton.exists && scrolls < 4 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue (testButton.waitForExistence(timeout: 5), "Test button not reachable")
        testButton.tap()
        let okLabel = app.staticTexts.matching (NSPredicate (format: "label BEGINSWITH 'OK —'")).firstMatch
        XCTAssertTrue (okLabel.waitForExistence(timeout: 10), "Test did not succeed against the mock server")

        // The model menu should now offer the fetched list; pick one
        var menu = app.buttons["ai-model-menu"].firstMatch
        if !menu.exists {
            menu = app.otherElements["ai-model-menu"].firstMatch
        }
        if !menu.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue (menu.waitForExistence(timeout: 5), "Model menu not found")
        menu.tap()
        let fetchedModel = app.buttons["mock-gpt"].firstMatch
        XCTAssertTrue (fetchedModel.waitForExistence(timeout: 5), "Fetched model not in the menu")
        XCTAssertFalse (app.buttons["whisper-1"].exists, "Non-chat model should be filtered out")
        fetchedModel.tap()

        app.buttons["Save"].tap()

        // Make the mock provider active (there may be pre-existing providers)
        let activate = app.images["ai-activate-OpenAI-compatible"].firstMatch
        XCTAssertTrue (activate.waitForExistence(timeout: 5))
        activate.tap()

        // 2. Produce output in the local terminal.  Relaunch first — provider
        // configs persist, and a fresh launch gives the same reliable
        // navigation state as testLocalTerminalOpens.
        app.terminate()
        app.launch()
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }
        let terminalLink = app.staticTexts["Local Terminal"].firstMatch
        if !terminalLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (terminalLink.waitForExistence(timeout: 10))
        terminalLink.tap()
        XCTAssertTrue (app.navigationBars["Local Terminal"].waitForExistence(timeout: 10), "Local Terminal did not open")
        sleep (2)
        // Focus the terminal before typing (the sidebar may have stolen focus)
        app.coordinate (withNormalizedOffset: CGVector (dx: 0.7, dy: 0.4)).tap()
        sleep (1)
        app.typeText ("echo EXPLAIN-TEST-MARKER\n")
        usleep (500_000)

        // 3. Explain: preview shows the captured output, Send streams the answer
        app.buttons["ai-menu"].firstMatch.tap()
        let explainItem = app.buttons["Explain Output"].firstMatch
        XCTAssertTrue (explainItem.waitForExistence(timeout: 5), "AI menu did not open")
        explainItem.tap()
        let sendButton = app.buttons.matching (NSPredicate (format: "label BEGINSWITH 'Send to'")).firstMatch
        XCTAssertTrue (sendButton.waitForExistence(timeout: 5), "Explain preview did not open")
        sendButton.tap()

        let answer = app.staticTexts.matching (NSPredicate (format: "label CONTAINS 'openai-mock'")).firstMatch
        XCTAssertTrue (answer.waitForExistence(timeout: 15), "Streamed answer not visible")

        let attachment = XCTAttachment (screenshot: app.screenshot ())
        attachment.lifetime = .keepAlways
        add (attachment)
    }

    /// NL→shell against the mock provider: request → suggested command with
    /// risk badge → insert (no newline).  Requires mock_sse.py on 127.0.0.1:8765
    /// and reuses the provider saved by testExplainEndToEnd if present.
    func testCommandEndToEnd() throws {
        let app = XCUIApplication()
        app.launch()

        let dismiss = app.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }

        // Ensure the mock provider exists and is active
        let aiLink = app.staticTexts["AI"].firstMatch
        if !aiLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (aiLink.waitForExistence(timeout: 10))
        aiLink.tap()
        XCTAssertTrue (app.navigationBars["AI Providers"].waitForExistence(timeout: 5))
        let activate = app.images["ai-activate-OpenAI-compatible"].firstMatch
        if !activate.waitForExistence(timeout: 3) {
            app.navigationBars["AI Providers"].buttons.firstMatch.tap()
            let compatible = app.buttons["OpenAI-compatible…"].firstMatch
            XCTAssertTrue (compatible.waitForExistence(timeout: 5))
            compatible.tap()
            let urlField = app.textFields["Base URL"]
            XCTAssertTrue (urlField.waitForExistence(timeout: 5))
            urlField.tap()
            let existing = (urlField.value as? String) ?? ""
            urlField.typeText (String (repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 5))
            urlField.typeText ("http://127.0.0.1:8765")
            let keyField = app.secureTextFields["API key"]
            keyField.tap()
            keyField.typeText ("mock-key\n")
            app.buttons["Save"].tap()
        }
        XCTAssertTrue (activate.waitForExistence(timeout: 5))
        activate.tap()

        // Fresh launch for reliable sidebar navigation
        app.terminate()
        app.launch()
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }
        let terminalLink = app.staticTexts["Local Terminal"].firstMatch
        if !terminalLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (terminalLink.waitForExistence(timeout: 10))
        terminalLink.tap()
        sleep (2)

        // Ask for a command
        app.buttons["ai-menu"].firstMatch.tap()
        let commandItem = app.buttons["Get a Command"].firstMatch
        XCTAssertTrue (commandItem.waitForExistence(timeout: 5), "AI menu did not open")
        commandItem.tap()

        let requestField = app.textFields.firstMatch
        XCTAssertTrue (requestField.waitForExistence(timeout: 5), "Command sheet did not open")
        requestField.tap()
        requestField.typeText ("print a marker\n")

        app.buttons["Get Command"].firstMatch.tap()

        XCTAssertTrue (app.staticTexts["echo MOCK-CMD"].waitForExistence(timeout: 15), "Suggested command not shown")
        XCTAssertTrue (app.staticTexts["Safe"].exists, "Risk badge missing")

        let attachment = XCTAttachment (screenshot: app.screenshot ())
        attachment.lifetime = .keepAlways
        add (attachment)

        // Insert dismisses the sheet and types the command (no newline)
        app.buttons["Insert into terminal"].firstMatch.tap()
        XCTAssertFalse (app.staticTexts["echo MOCK-CMD"].waitForExistence(timeout: 3), "Sheet did not dismiss")
    }

    /// Diagnose mode: same sheet machinery as Explain, different framing.
    /// Requires mock_sse.py on 127.0.0.1:8765 and a provider saved by an
    /// earlier AI test (falls back to creating one).
    func testDiagnoseEndToEnd() throws {
        let app = XCUIApplication()
        app.launch()

        let dismiss = app.buttons["Dismiss"]
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }

        let aiLink = app.staticTexts["AI"].firstMatch
        if !aiLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (aiLink.waitForExistence(timeout: 10))
        aiLink.tap()
        XCTAssertTrue (app.navigationBars["AI Providers"].waitForExistence(timeout: 5))
        let activate = app.images["ai-activate-OpenAI-compatible"].firstMatch
        XCTAssertTrue (activate.waitForExistence(timeout: 5), "Run testExplainEndToEnd first to create the mock provider")
        activate.tap()

        app.terminate()
        app.launch()
        if dismiss.waitForExistence(timeout: 5) {
            dismiss.tap()
        }
        let terminalLink = app.staticTexts["Local Terminal"].firstMatch
        if !terminalLink.waitForExistence(timeout: 3) {
            app.navigationBars.buttons.firstMatch.tap()
        }
        XCTAssertTrue (terminalLink.waitForExistence(timeout: 10))
        terminalLink.tap()
        sleep (2)
        app.typeText ("ls /definitely-missing-path\n")
        usleep (500_000)

        app.buttons["ai-menu"].firstMatch.tap()
        let diagnoseItem = app.buttons["Diagnose Failure"].firstMatch
        XCTAssertTrue (diagnoseItem.waitForExistence(timeout: 5), "AI menu did not open")
        diagnoseItem.tap()

        // Diagnose framing: its own title and a larger scrollback window
        XCTAssertTrue (app.navigationBars["Diagnose"].waitForExistence(timeout: 5), "Diagnose sheet did not open")
        XCTAssertTrue (app.staticTexts["Last 150 lines"].exists, "Diagnose should capture more scrollback than Explain")

        let sendButton = app.buttons.matching (NSPredicate (format: "label BEGINSWITH 'Send to'")).firstMatch
        XCTAssertTrue (sendButton.waitForExistence(timeout: 5))
        sendButton.tap()

        let answer = app.staticTexts.matching (NSPredicate (format: "label CONTAINS 'openai-mock'")).firstMatch
        XCTAssertTrue (answer.waitForExistence(timeout: 15), "Streamed diagnosis not visible")

        let attachment = XCTAttachment (screenshot: app.screenshot ())
        attachment.lifetime = .keepAlways
        add (attachment)
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
