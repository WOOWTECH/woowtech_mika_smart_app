import Foundation

@main
enum CheckChatScrollFollow {
    static func main() {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool) {
            precondition(condition())
            assertions += 1
        }
        func sample(_ height: Double, _ bottom: Double, _ viewport: Double = 500) -> ChatTranscriptViewport {
            ChatTranscriptViewport(contentHeight: height, bottomY: bottom, viewportHeight: viewport)
        }

        var follow = ChatScrollFollowPolicy()
        expect(follow.observe(sample(1200, 1200))) // first display
        expect(!follow.observe(sample(1200, 500))) // initial scrollTo moves the content
        expect(follow.followsTail)

        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1380, 1050))) // drag plus streamed growth in one layout pass
        expect(!follow.observe(sample(1380, 740))) // exactly 240 points, but finger is still down
        expect(!follow.followsTail)
        follow.endDrag()
        let beforeDeceleration = follow.pendingSettleRevision!
        expect(!follow.observe(sample(1380, 690))) // deceleration invalidates the first timer
        expect(!follow.settle(expectedRevision: beforeDeceleration))
        expect(!follow.followsTail)
        let settled = follow.pendingSettleRevision!
        expect(follow.settle(expectedRevision: settled)) // caller waited for geometry to go quiet
        expect(follow.followsTail)
        expect(!follow.observe(sample(1490, 720))) // offset changed with content; no forced jump
        expect(follow.followsTail)
        expect(follow.observe(sample(1600, 830))) // growth at fixed offset follows the tail

        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        expect(!follow.observe(sample(1710, 1010))) // content and position moved together
        follow.endDrag()
        let beforeKeyboard = follow.pendingSettleRevision!
        expect(!follow.observe(sample(1710, 1010, 420))) // keyboard resize cannot rearm during settle
        expect(!follow.settle(expectedRevision: beforeKeyboard))
        expect(!follow.followsTail)
        expect(follow.settle(expectedRevision: follow.pendingSettleRevision!))
        expect(!follow.followsTail) // still farther than 240 points from the tail
        expect(!follow.observe(sample(1820, 1120, 420))) // later streamed text cannot pull reader
        expect(!follow.observe(sample(1820, 1120, 500))) // keyboard closes while reading earlier
        expect(!follow.followsTail)

        follow.userSubmitted() // explicit send resumes follow even while previously reading above
        expect(follow.followsTail)
        expect(follow.pendingSettleRevision == nil)
        expect(follow.observe(sample(1820, 1120, 500)))
        expect(follow.observe(sample(1930, 1230, 500)))
        expect(follow.observe(sample(1930, 1230, 420))) // keyboard opens while following a new answer

        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        follow.endDrag()
        let oldConversationTimer = follow.pendingSettleRevision!
        follow.conversationChanged() // real conversation identity, even empty to empty
        expect(!follow.settle(expectedRevision: oldConversationTimer))
        expect(follow.followsTail)
        expect(follow.observe(sample(0, 0)))
        expect(!follow.observe(sample(.infinity, 0))) // invalid geometry cannot cause a jump
        print("CHAT_SCROLL_FOLLOW assertions=\(assertions) status=PASS")
    }
}
