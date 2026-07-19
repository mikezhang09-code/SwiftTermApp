import XCTest

/// Walks every guide topic and fails if any unresolved {symbol} token is
/// visible, which is how helpTextWithSymbols renders a name that does not
/// exist in SF Symbols.
class GuideAuditTests: XCTestCase {
    func testNoUnresolvedSymbolTokens() throws {
        continueAfterFailure = true
        let app = XCUIApplication(); app.launch()
        let d = app.buttons["Dismiss"]
        if d.waitForExistence(timeout: 5) { d.tap() }
        let h = app.buttons["Help"].firstMatch
        var t = 0
        while !h.exists && t < 6 { app.swipeUp(); t += 1 }
        XCTAssertTrue(h.waitForExistence(timeout: 8)); h.tap()

        let topics = ["Getting Started", "Hosts and Connections", "SSH Keys and Known Hosts",
                      "The Keyboard", "Files and Transfers", "Snippets", "Port Forwarding",
                      "AI Assistance", "Settings", "Troubleshooting"]
        var bad: [String] = []

        for name in topics {
            // Scroll the hub until the topic is visible
            var tries = 0
            while !app.staticTexts[name].exists && tries < 8 { app.swipeUp(); tries += 1 }
            guard app.staticTexts[name].exists else {
                bad.append("MISSING TOPIC: \(name)"); continue
            }
            app.staticTexts[name].tap()
            sleep(1)

            // Page through the topic collecting any literal braces
            for _ in 0..<6 {
                for label in app.staticTexts.allElementsBoundByIndex.map({ $0.label }) {
                    if label.contains("{") || label.contains("}") {
                        bad.append("\(name): \(label.prefix(80))")
                    }
                }
                app.swipeUp()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            sleep(1)
            // Back at the hub, scroll to top for the next lookup
            for _ in 0..<8 { app.swipeDown() }
        }

        print("AUDIT-FINDINGS: \(Set(bad).sorted())")
        XCTAssertTrue(bad.isEmpty, "Unresolved symbol tokens or missing topics: \(Set(bad).sorted())")
    }
}
