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
        expect(follow.observe(sample(1200, 1200))) // first display follows the latest answer
        expect(!follow.observe(sample(1200, 500))) // programmatic scroll settled
        expect(follow.followsTail)
        expect(!follow.observe(sample(1200, 870))) // reader scrolled 370 points up
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1380, 1050))) // a new streamed chunk cannot pull the reader
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1380, 710))) // reader returned within 240 points of the tail
        expect(follow.followsTail)
        expect(follow.observe(sample(1490, 820))) // next chunk follows again

        follow.userDraggedTowardEarlierContent()
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1600, 930))) // simultaneous drag and text growth stays put
        expect(!follow.observe(sample(1600, 900, 420))) // keyboard/viewport resize does not restore follow
        expect(!follow.followsTail)
        follow.conversationChanged()
        expect(follow.observe(sample(1200, 1200))) // opening a different conversation resets the rule
        expect(follow.followsTail)
        expect(!follow.observe(sample(.infinity, 0))) // invalid layout never triggers a jump
        print("CHAT_SCROLL_FOLLOW assertions=\(assertions) status=PASS")
    }
}
