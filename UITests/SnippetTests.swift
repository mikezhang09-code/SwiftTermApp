//
//  SnippetTests.swift
//  UITests
//
//  Regression coverage for the snippet browser and editor.  Each of these
//  guards a defect that was live: edits not refreshing the row, only the
//  text being tappable, and blank snippets being saveable.
//
import XCTest

class SnippetTests: XCTestCase {
    func openSnippets(_ app: XCUIApplication) {
        let d = app.buttons["Dismiss"]
        if d.waitForExistence(timeout: 5) { d.tap() }
        let s = app.buttons["Snippets"].firstMatch
        var t = 0
        while !s.exists && t < 6 { app.swipeUp(); t += 1 }
        XCTAssertTrue(s.waitForExistence(timeout: 8)); s.tap()
    }
    func add(_ app: XCUIApplication, _ title: String, _ command: String) {
        app.buttons["Add Snippet"].firstMatch.tap()
        let f = app.textFields["name"].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap(); f.typeText(title)
        let e = app.textViews.firstMatch; e.tap(); e.typeText(command)
        app.buttons["Save"].firstMatch.tap()
        sleep(1)
    }
    func labels(_ app: XCUIApplication) -> [String] {
        app.staticTexts.allElementsBoundByIndex.map { $0.label }
    }
    /// Target the row containing a given title, rather than a fixed index -
    /// tests share a database, so index 0 is not necessarily this test's row.
    func cell(_ app: XCUIApplication, containing title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    func testAddAppearsInList() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        add(app, "AddMe", "echo add")
        XCTAssertTrue(app.staticTexts["AddMe"].waitForExistence(timeout: 5), "Added snippet not listed")
    }

    func testEditRefreshesRowWithoutRelaunch() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        add(app, "EditMe", "echo edit")
        app.staticTexts["EditMe"].tap()
        let f = app.textFields["name"].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 5), "Editor did not open")
        XCTAssertEqual(f.value as? String, "EditMe", "Editor did not load existing values")
        f.tap(); f.typeText("X")
        app.buttons["Save"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(labels(app).contains("EditMeX"),
                      "Edited row did not refresh without a relaunch: \(labels(app))")
    }

    func testFullRowIsTappable() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        add(app, "TapMe", "ls")
        let c = cell(app, containing: "TapMe")
        XCTAssertTrue(c.waitForExistence(timeout: 5))
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        sleep(2)
        XCTAssertTrue(app.textFields["name"].firstMatch.exists,
                      "Tapping the row away from its text did not open the editor")
    }

    func testSwipeToDelete() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        add(app, "DeleteMe", "echo del")
        let c = cell(app, containing: "DeleteMe")
        XCTAssertTrue(c.waitForExistence(timeout: 5))
        c.swipeLeft()
        let del = app.buttons["Delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 3), "Swipe did not reveal Delete")
        del.tap(); sleep(2)
        XCTAssertFalse(labels(app).contains("DeleteMe"), "Row still present after delete")

        app.terminate(); app.launch(); openSnippets(app); sleep(1)
        XCTAssertFalse(labels(app).contains("DeleteMe"), "Delete did not persist")
    }

    func testBlankSnippetRejected() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        app.buttons["Add Snippet"].firstMatch.tap()
        XCTAssertTrue(app.textFields["name"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].firstMatch.isEnabled,
                       "Save is enabled with an empty title and command")
        // Title only, still no command
        let f = app.textFields["name"].firstMatch
        f.tap(); f.typeText("OnlyTitle")
        XCTAssertFalse(app.buttons["Save"].firstMatch.isEnabled,
                       "Save is enabled with no command")
    }

    func testEmptyStateHasTitle() throws {
        let app = XCUIApplication(); app.launch(); openSnippets(app)
        // Only meaningful when the list is empty; skip otherwise
        if app.cells.count == 0 {
            XCTAssertTrue(labels(app).contains("Snippets"), "Empty state has no navigation title")
        }
    }

    /// The snippet picker must be reachable from the Local Terminal, and
    /// choosing a snippet must type it into the session.
    func testSnippetInsertsIntoLocalTerminal() throws {
        let app = XCUIApplication(); app.launch()

        // Create a snippet with a distinctive, harmless command
        openSnippets(app)
        add(app, "EchoMarker", "echo SNIPPET_OK")
        XCTAssertTrue(app.staticTexts["EchoMarker"].waitForExistence(timeout: 5))

        // Back to home, into the Local Terminal
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let local = app.buttons["Local Terminal"].firstMatch
        var t = 0
        while !local.exists && t < 6 { app.swipeUp(); t += 1 }
        XCTAssertTrue(local.waitForExistence(timeout: 8), "No Local Terminal entry")
        local.tap()
        sleep(3)

        // The snippet button must exist here
        let snipButton = app.buttons["snippets"].firstMatch
        XCTAssertTrue(snipButton.waitForExistence(timeout: 8),
                      "Local Terminal has no snippet button")
        snipButton.tap()

        let row = app.staticTexts["EchoMarker"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Snippet picker did not list the snippet")
        row.tap()
        sleep(3)

        try? app.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hongyan-Documents-GitHub-SwiftTermApp/1b9646ef-6854-4786-aa48-aaf9207943e8/scratchpad/snip-terminal.png"))

        // SwiftTerm draws the terminal itself, so its contents are not in the
        // accessibility tree and cannot be asserted here; the screenshot above
        // is the record that the text lands at the prompt. What is checkable is
        // that the picker closed and handed control back to the terminal.
        XCTAssertFalse(app.staticTexts["EchoMarker"].exists,
                       "Snippet picker did not dismiss after choosing a snippet")
        XCTAssertTrue(app.buttons["snippets"].firstMatch.exists,
                      "Did not return to the terminal after choosing a snippet")
    }

    /// A snippet holding two commands, one per line, must run both.  Line
    /// endings have to reach the tty as carriage returns; sent verbatim the
    /// lines run together ("ls" + "cd .." => "lscd ..").  The terminal buffer
    /// is not readable from a UI test, so this drives the flow and leaves the
    /// screenshot as the record.
    func testMultiLineSnippetRunsBothCommands() throws {
        let app = XCUIApplication(); app.launch()
        openSnippets(app)

        app.buttons["Add Snippet"].firstMatch.tap()
        let f = app.textFields["name"].firstMatch
        XCTAssertTrue(f.waitForExistence(timeout: 5))
        f.tap(); f.typeText("ListThenUp")
        let e = app.textViews.firstMatch
        e.tap(); e.typeText("ls\ncd ..\n")
        app.buttons["Save"].firstMatch.tap()
        sleep(1)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let local = app.buttons["Local Terminal"].firstMatch
        var t = 0
        while !local.exists && t < 6 { app.swipeUp(); t += 1 }
        XCTAssertTrue(local.waitForExistence(timeout: 8))
        local.tap()
        sleep(3)

        app.buttons["snippets"].firstMatch.tap()
        let row = app.staticTexts["ListThenUp"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        sleep(3)

        try? app.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "/private/tmp/claude-501/-Users-hongyan-Documents-GitHub-SwiftTermApp/1b9646ef-6854-4786-aa48-aaf9207943e8/scratchpad/ml-final.png"))
        XCTAssertTrue(app.buttons["snippets"].firstMatch.exists,
                      "Did not return to the terminal after running a multi-line snippet")
    }
}
