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
        expect(follow.observe(sample(1200, 1200)))
        expect(!follow.observe(sample(1200, 500))) // first scrollTo reaches the tail
        expect(follow.followsTail)

        // A short transcript cannot scroll. Even a large finger movement and
        // temporary rubber-band bounce must not turn off following.
        var noOpDragAtBottom = ChatScrollFollowPolicy()
        expect(noOpDragAtBottom.observe(sample(300, 300)))
        noOpDragAtBottom.beginDrag()
        noOpDragAtBottom.userDraggedTowardEarlierContent()
        expect(!noOpDragAtBottom.observe(sample(300, 355)))
        noOpDragAtBottom.endDrag()
        let bouncingRevision = noOpDragAtBottom.pendingSettleRevision!
        expect(!noOpDragAtBottom.observe(sample(300, 300)))
        expect(!noOpDragAtBottom.settle(expectedRevision: bouncingRevision))
        expect(noOpDragAtBottom.settle(expectedRevision: noOpDragAtBottom.pendingSettleRevision!))
        expect(noOpDragAtBottom.followsTail)
        noOpDragAtBottom.beginDrag()
        noOpDragAtBottom.userDraggedTowardEarlierContent()
        expect(!noOpDragAtBottom.observe(sample(900, 900))) // growth, no reader movement
        noOpDragAtBottom.endDrag()
        expect(noOpDragAtBottom.settle(expectedRevision: noOpDragAtBottom.pendingSettleRevision!))
        expect(noOpDragAtBottom.followsTail)
        expect(noOpDragAtBottom.needsTailScroll) // catch up to the new fragment
        expect(!noOpDragAtBottom.observe(sample(900, 500)))
        expect(!noOpDragAtBottom.needsTailScroll)
        expect(noOpDragAtBottom.observe(sample(1000, 600)))

        // A platform scroll can arrive without a DragGesture. Growth alone
        // keeps the content-origin offset constant and should follow.
        var growthOnly = ChatScrollFollowPolicy()
        expect(growthOnly.observe(sample(1200, 500)))
        expect(growthOnly.observe(sample(1320, 620)))
        expect(growthOnly.followsTail)

        // Counterexample: +120 content height and +120 movement toward earlier
        // text are delivered in one geometry update. The origin offset falls
        // from 700 to 580; returning true here would steal the reader's place.
        var mergedScrollAndGrowth = ChatScrollFollowPolicy()
        expect(mergedScrollAndGrowth.observe(sample(1200, 500)))
        expect(!mergedScrollAndGrowth.observe(sample(1320, 740)))
        expect(!mergedScrollAndGrowth.followsTail)
        expect(!mergedScrollAndGrowth.observe(sample(1440, 860)))
        expect(!mergedScrollAndGrowth.followsTail)
        var mergedWithViewportChange = ChatScrollFollowPolicy()
        expect(mergedWithViewportChange.observe(sample(1200, 500)))
        expect(!mergedWithViewportChange.observe(sample(1320, 740, 420)))
        expect(!mergedWithViewportChange.followsTail)

        // An intentional small upward scroll is a reading choice, even though
        // it ends well inside the former 240-point auto-rearm window.
        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        expect(follow.followsTail) // finger direction is not yet actual motion
        expect(!follow.observe(sample(1200, 620))) // 120 points above the tail
        follow.endDrag()
        let smallScrollRevision = follow.pendingSettleRevision!
        expect(follow.settle(expectedRevision: smallScrollRevision))
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1320, 740))) // real later chunk, fixed reading offset
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1320, 740, 420))) // keyboard cannot release reading hold
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1320, 740, 500)))
        expect(!follow.followsTail)
        var layoutShift = follow
        expect(!layoutShift.observe(sample(1320, 500))) // geometry at the end is not proof of user intent
        expect(!layoutShift.followsTail)
        layoutShift.userRequestedLatest() // accessible button, independent of DragGesture
        expect(layoutShift.followsTail)
        expect(layoutShift.observe(sample(1440, 620)))

        // A deliberate upward finger movement toward the latest message still
        // needs to reach the physical end, not merely within 240 points.
        follow.beginDrag()
        follow.userDraggedTowardLatestContent()
        expect(!follow.observe(sample(1320, 518))) // 18 points short of the end
        follow.endDrag()
        expect(follow.settle(expectedRevision: follow.pendingSettleRevision!))
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1440, 638))) // another chunk cannot pull it
        expect(!follow.followsTail)
        follow.beginDrag()
        follow.userDraggedTowardLatestContent()
        expect(!follow.observe(sample(1440, 510))) // actual bottom within layout tolerance
        follow.endDrag()
        let beforeDeceleration = follow.pendingSettleRevision!
        expect(!follow.observe(sample(1440, 504)))
        expect(!follow.settle(expectedRevision: beforeDeceleration))
        expect(!follow.followsTail)
        expect(follow.settle(expectedRevision: follow.pendingSettleRevision!))
        expect(follow.followsTail)
        expect(follow.observe(sample(1550, 614))) // next chunk follows after explicit return

        // Content height and position changing together must not override an
        // active finger drag, even when the displayed edge looks near the end.
        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        expect(!follow.observe(sample(1660, 800))) // 200+ points above the tail
        expect(!follow.observe(sample(1770, 910))) // both content and bottom move
        follow.endDrag()
        expect(follow.settle(expectedRevision: follow.pendingSettleRevision!))
        expect(!follow.followsTail)
        expect(!follow.observe(sample(1880, 1020)))
        expect(!follow.followsTail)

        // Two quick flicks back to the end: the first reaches it and the second
        // starts before the first settled, only bouncing there. Together they
        // move toward the latest text and resume following (iPhone 16 Pro Max,
        // run 43606357170, kept showing 回到最新訊息 at the end).
        var twoFlicks = ChatScrollFollowPolicy()
        expect(twoFlicks.observe(sample(1200, 500)))
        twoFlicks.beginDrag()
        twoFlicks.userDraggedTowardEarlierContent()
        expect(!twoFlicks.observe(sample(1200, 800)))
        twoFlicks.endDrag()
        expect(twoFlicks.settle(expectedRevision: twoFlicks.pendingSettleRevision!))
        expect(!twoFlicks.followsTail)
        twoFlicks.beginDrag()
        twoFlicks.userDraggedTowardLatestContent()
        expect(!twoFlicks.observe(sample(1200, 500))) // the first flick reaches the end
        twoFlicks.endDrag()
        twoFlicks.beginDrag() // before the first settled
        twoFlicks.userDraggedTowardLatestContent()
        expect(!twoFlicks.observe(sample(1200, 460))) // rubber band past the end
        expect(!twoFlicks.observe(sample(1200, 500)))
        twoFlicks.endDrag()
        expect(twoFlicks.settle(expectedRevision: twoFlicks.pendingSettleRevision!))
        expect(twoFlicks.followsTail)
        // A drag after the previous one settled still starts fresh: a bounce at
        // the end while reading earlier does not resume following by itself.
        var settledBounce = ChatScrollFollowPolicy()
        expect(settledBounce.observe(sample(1200, 500)))
        settledBounce.beginDrag()
        settledBounce.userDraggedTowardEarlierContent()
        expect(!settledBounce.observe(sample(1200, 800)))
        settledBounce.endDrag()
        expect(settledBounce.settle(expectedRevision: settledBounce.pendingSettleRevision!))
        expect(!settledBounce.observe(sample(1200, 500))) // passive motion to the end
        expect(!settledBounce.followsTail)
        settledBounce.beginDrag()
        settledBounce.userDraggedTowardLatestContent()
        expect(!settledBounce.observe(sample(1200, 460)))
        expect(!settledBounce.observe(sample(1200, 500)))
        settledBounce.endDrag()
        expect(settledBounce.settle(expectedRevision: settledBounce.pendingSettleRevision!))
        expect(!settledBounce.followsTail)

        follow.userSubmitted() // a newly accepted send always resumes follow
        expect(follow.followsTail)
        expect(follow.pendingSettleRevision == nil)
        expect(follow.observe(sample(1880, 850)))
        expect(follow.observe(sample(1990, 960)))
        expect(follow.observe(sample(1990, 960, 420))) // keyboard while following

        follow.beginDrag()
        follow.userDraggedTowardEarlierContent()
        follow.endDrag()
        let oldConversationTimer = follow.pendingSettleRevision!
        follow.conversationChanged() // includes empty to empty conversation changes
        expect(!follow.settle(expectedRevision: oldConversationTimer))
        expect(follow.followsTail)
        expect(follow.observe(sample(0, 0)))
        expect(!follow.observe(sample(.infinity, 0)))
        // Browsing a long empty-state list must not be pinned to the tail,
        // including accessibility scrolls and text-size/viewport changes.
        var emptyBrowsing = ChatScrollFollowPolicy()
        expect(!emptyBrowsing.observe(sample(1800, 1800), hasTranscript: false))
        expect(!emptyBrowsing.observe(sample(1800, 1000), hasTranscript: false))
        expect(!emptyBrowsing.observe(sample(2600, 1700, 300), hasTranscript: false))
        expect(!emptyBrowsing.needsTailScroll)
        expect(emptyBrowsing.observe(sample(600, 600), hasTranscript: true))
        expect(!emptyBrowsing.observe(sample(600, 500), hasTranscript: true))

        print("CHAT_SCROLL_FOLLOW assertions=\(assertions) status=PASS")
    }
}
