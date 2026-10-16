import XCTest

/// The owner's T02 answer (2026-10-16): Today asks which fasts a person keeps
/// instead of assuming. What only a UI test can show: the card is on Today, its
/// answer is saved, and it is not asked again after a relaunch. What the answer
/// does to the fasting schedule is `ReligiousFastingDerivationTests.fastsQuestion`.
final class FastsQuestionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDownWithError() throws {
        // Leave the defaults behind (Ramadan on, the other two off), answered.
        app.terminate()
        app.launchArguments += ["-AlmanacAskFastsAgain"]
        app.launch()
        let save = app.buttons["fasts-question-save"]
        if app.reveal(save) { save.tap() }
    }

    func testTodayAsksWhichFastsAndDoesNotAskAgain() throws {
        app.launchArguments += ["-AlmanacAskFastsAgain"]
        app.launch()
        XCTAssertFalse(app.staticTexts["Almanac could not open"].waitForExistence(timeout: 5))

        let question = app.staticTexts["Which fasts do you keep?"]
        XCTAssertTrue(question.waitForExistence(timeout: 15), "Today does not ask which fasts are kept")
        let ramadan = app.switches["fasts-question-ramadan"]
        let monThu = app.switches["fasts-question-mon-thu"]
        let whiteDays = app.switches["fasts-question-white-days"]
        XCTAssertTrue(app.reveal(whiteDays), "the question's switches are not reachable")
        XCTAssertEqual(ramadan.value as? String, "1", "Ramadan should start on")
        XCTAssertEqual(monThu.value as? String, "0", "Mondays and Thursdays should start off")
        XCTAssertEqual(whiteDays.value as? String, "0", "the White Days should start off")

        monThu.tapSwitchControl()
        XCTAssertTrue(app.waitUntil(timeout: 5) { monThu.value as? String == "1" }, "the switch did not move")
        let save = app.buttons["fasts-question-save"]
        XCTAssertTrue(app.reveal(save))
        save.tap()
        XCTAssertTrue(app.waitUntil(timeout: 10) { !question.exists }, "the question stayed after it was answered")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-AlmanacAskFastsAgain" }
        app.launch()
        XCTAssertTrue(app.buttons["Modules"].waitForExistence(timeout: 15))
        XCTAssertFalse(question.waitForExistence(timeout: 3), "the question was asked again after a relaunch")
    }
}
