#if !SKILLS_CORE_SMOKE
import XCTest

final class SkillsCoreTests: XCTestCase {
    func testDocumentsAndValidation() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.documents(), 0) }
    func testReviewAndOptimisticRevisions() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.reviewAndRevisions(), 0) }
    func testConfirmedSkillDeletionRejectsStaleSelection() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.deletionReview(), 0) }
    func testDirectRestorePreservesHistoryAndRejectsStaleSelection() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.restoreTarget(), 0) }
    func testOutcomeLifecycle() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.outcomeLifecycle(), 0) }
    func testTrustedJudgementAndLearningGates() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.learningGates(), 0) }
    func testRetrievalAndNonAuthorizingContext() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.retrievalAndContext(), 0) }
    func testCapabilityRevalidationAndResourceBounds() throws { XCTAssertGreaterThan(try SkillsCoreFixtures.capabilitiesAndBounds(), 0) }
}
#endif
