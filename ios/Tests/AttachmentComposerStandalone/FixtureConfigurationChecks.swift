import Foundation

@main enum FixtureConfigurationChecks {
    static func main() {
        let id = UUID().uuidString
        let base = ["app", "-UITestMode", "-UITestNamespace", id, "-UITestResetStorage", "-UITestAttachmentComposer"]
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        check(ChatAttachmentComposerUITestFixture.valid(arguments: base, simulator: true), "valid isolated simulator")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base, simulator: false), "physical device denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base.filter { $0 != "-UITestMode" }, simulator: true), "test mode required")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base.filter { $0 != "-UITestNamespace" }, simulator: true), "namespace required")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base.map { $0 == id ? "not-a-uuid" : $0 }, simulator: true), "namespace must be UUID")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-UITestAttachmentComposer"], simulator: true), "duplicate flag denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-UITestMode"], simulator: true), "duplicate test mode denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-UITestNamespace", id], simulator: true), "duplicate namespace denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-UITestResetStorage"], simulator: true), "duplicate reset denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-LiveModelUITest"], simulator: true), "live mode denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base + ["-UITestVoiceFixture"], simulator: true), "other fixture denied")
        check(!ChatAttachmentComposerUITestFixture.valid(arguments: base.map { $0 == "-UITestAttachmentComposer" ? "-UITestAttachmentComposerExtra" : $0 }, simulator: true), "unknown prefixed flag denied")
        check(ChatAttachmentComposerUITestFixture.selected(arguments: ["app"]) == nil, "ordinary app has no fixture")
        print("Attachment composer fixture configuration: 13 passed")
    }
}
