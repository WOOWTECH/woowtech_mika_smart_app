import XCTest

/// Navigate through the same Settings > Model link and native Back control
/// that people use. These tests launch with zh-Hant; localized titles have a
/// separate language UI check.
///
/// The model page lists providers as the Play build does. While there is no
/// provider its add form is open; the tests type their own service, so this
/// picks 自訂 to show the base URL field (settings.baseURL) next to
/// settings.model and settings.apiKey. With a provider saved, the form stays
/// closed until 新增服務商.
func openModelSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let root = app.navigationBars["設定"]
    XCTAssertTrue(root.waitForExistence(timeout: 10), file: file, line: line)
    let link = app.buttons["settings.modelJump"]
    XCTAssertTrue(link.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(link.isEnabled && link.isHittable, file: file, line: line)
    XCTAssertFalse(app.textFields["settings.baseURL"].exists,
                   "Model fields belong to the destination, not the Settings root.", file: file, line: line)
    link.tap()
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.buttons["models.role.main"].waitForExistence(timeout: 10), file: file, line: line)
    let custom = app.buttons["setup.preset.custom"]
    if custom.waitForExistence(timeout: 2) {
        revealLearningElement(custom, in: app, file: file, line: line)
        custom.tap()
        XCTAssertTrue(app.textFields["settings.baseURL"].waitForExistence(timeout: 10), file: file, line: line)
    }
    XCTAssertFalse(link.isHittable, file: file, line: line)
    XCTAssertFalse(app.buttons["section.back"].isHittable,
                   "The root shortcut must not cover the native model-detail Back button.", file: file, line: line)
}

func returnFromModelSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let detail = app.navigationBars["模型"]
    XCTAssertTrue(detail.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertFalse(app.buttons["section.back"].isHittable,
                   "Model detail must return to Settings one level at a time.", file: file, line: line)
    let back = detail.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isEnabled && back.isHittable,
                  file: file, line: line)
    back.tap()
    XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.buttons["settings.modelJump"].waitForExistence(timeout: 5), file: file, line: line)
    XCTAssertFalse(app.textFields["settings.baseURL"].isHittable, file: file, line: line)
}

/// After a tap on 不測試，直接儲存 (settings.save): confirm 仍然儲存. As on the
/// Play build the provider is saved untested and its model is not made the
/// main model, so no consent is asked (chooseMainAfterUntestedSave does that).
/// Tests that need a main model at once use 測試並儲存 (setup.test) and
/// agreeToModelConsent instead.
func confirmModelSave(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertEqual(alert.label, "不測試就儲存？", file: file, line: line)
    let save = alert.buttons["仍然儲存"]
    XCTAssertTrue(save.waitForExistence(timeout: 5), file: file, line: line)
    save.tap()
    XCTAssertFalse(app.buttons["consent.agree"].waitForExistence(timeout: 2),
                   "Saving without a test makes no main model, so it asks no consent.", file: file, line: line)
}

/// After 不測試，直接儲存 with no main model yet: 選主模型 (setup.pickMain) opens
/// the picker; the chosen model is tested first, then the consent is asked
/// (App Review 5.1.2(i)) and the model becomes the main model.
func chooseMainAfterUntestedSave(_ model: String, in app: XCUIApplication,
                                 file: StaticString = #filePath, line: UInt = #line) {
    let pick = app.buttons["setup.pickMain"]
    XCTAssertTrue(pick.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(pick, in: app, file: file, line: line)
    pick.tap()
    XCTAssertTrue(app.navigationBars["主模型"].waitForExistence(timeout: 10), file: file, line: line)
    let row = app.buttons["picker.model." + model]
    XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(row, in: app, file: file, line: line)
    row.tap()
    agreeToModelConsent(in: app, file: file, line: line)
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 15), file: file, line: line)
    let main = app.buttons["models.role.main"]
    let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", model), object: main)
    XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 10), .completed, file: file, line: line)
}

/// The consent screen names the service and its host; 同意並繼續 records the
/// consent and goes on with what asked for it.
func agreeToModelConsent(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    answerModelConsent(agree: true, in: app, file: file, line: line)
}

func answerModelConsent(agree: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let button = app.buttons[agree ? "consent.agree" : "consent.decline"]
    XCTAssertTrue(button.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.staticTexts["consent.body"].exists, file: file, line: line)
    let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed, file: file, line: line)
    button.tap()
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: button)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
}

/// From the model page, a provider's page (its name is the navigation title).
func openModelProvider(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let row = app.buttons["models.provider." + name]
    XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(row, in: app, file: file, line: line)
    row.tap()
    XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.buttons["provider.delete"].waitForExistence(timeout: 10), file: file, line: line)
}

/// From a provider's page back to the model page, with the native Back control.
func returnFromModelProvider(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let bar = app.navigationBars[name]
    XCTAssertTrue(bar.waitForExistence(timeout: 10), file: file, line: line)
    let back = bar.buttons.matching(NSPredicate(format: "identifier != %@", "section.back")).firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isEnabled && back.isHittable, file: file, line: line)
    back.tap()
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 10), file: file, line: line)
}

/// From the model page: delete a provider and its key (刪除這個服務商 › 刪除),
/// back on the model page.
func deleteModelProvider(_ name: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    openModelProvider(name, in: app, file: file, line: line)
    let delete = app.buttons["provider.delete"]
    revealLearningElement(delete, in: app, file: file, line: line)
    delete.tap()
    let alert = app.alerts.firstMatch
    XCTAssertTrue(alert.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertEqual(alert.label, "刪除「\(name)」？", file: file, line: line)
    let confirm = alert.buttons["刪除"]
    XCTAssertTrue(confirm.waitForExistence(timeout: 5), file: file, line: line)
    confirm.tap()
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 10), file: file, line: line)
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                         object: app.buttons["models.provider." + name])
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
}

/// From the model page: a provider's model, then its 用作 sheet.
func openModelUseAs(provider: String, model: String, in app: XCUIApplication,
                    file: StaticString = #filePath, line: UInt = #line) {
    openModelProvider(provider, in: app, file: file, line: line)
    let row = app.buttons["provider.model." + model]
    XCTAssertTrue(row.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(row, in: app, file: file, line: line)
    row.tap()
    XCTAssertTrue(app.buttons["useAs.cancel"].waitForExistence(timeout: 10), file: file, line: line)
}

/// Close the 用作 sheet (its answers apply at once) and go back to the model page.
func closeModelUseAs(provider: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let cancel = app.buttons["useAs.cancel"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 5), file: file, line: line)
    cancel.tap()
    let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: cancel)
    XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
    returnFromModelProvider(provider, in: app, file: file, line: line)
}

/// From the model page: type a model name for a provider in the main-model
/// picker and tap 使用. The test call passes on the fixture model, the model
/// becomes the main one and the picker closes. A provider other than the one
/// agreed to asks for consent first.
func chooseTypedMainModel(_ model: String, provider: String, consent: Bool = false, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) {
    let main = app.buttons["models.role.main"]
    XCTAssertTrue(main.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(main, in: app, file: file, line: line)
    main.tap()
    XCTAssertTrue(app.navigationBars["主模型"].waitForExistence(timeout: 10), file: file, line: line)
    let field = app.textFields["picker.manual." + provider]
    XCTAssertTrue(field.waitForExistence(timeout: 10), file: file, line: line)
    revealLearningElement(field, in: app, file: file, line: line)
    field.tap()
    field.typeText(model)
    XCTAssertEqual(field.value as? String, model, file: file, line: line)
    let use = app.buttons["picker.use." + provider]
    revealLearningElement(use, in: app, file: file, line: line)
    use.tap()
    if consent { agreeToModelConsent(in: app, file: file, line: line) }
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 15), file: file, line: line)
    let chosen = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", model), object: main)
    XCTAssertEqual(XCTWaiter.wait(for: [chosen], timeout: 10), .completed, file: file, line: line)
}
