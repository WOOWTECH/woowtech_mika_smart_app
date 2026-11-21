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

        // A tail scroll can make lazy rows measure again, so the geometry can
        // swing between two heights with the reader's place unchanged. Without
        // new content the scrolls stop after a few: layout and scrolling cannot
        // feed each other forever. New content or the person's request resumes them.
        var swinging = ChatScrollFollowPolicy()
        var granted = 0
        for step in 0..<40 where swinging.observe(step % 2 == 0 ? sample(3000, 2000) : sample(2900, 1900)) { granted += 1 }
        expect(granted == ChatScrollFollowPolicy.maximumTailScrollsWithoutGrowth)
        expect(swinging.followsTail)
        expect(swinging.observe(sample(3300, 2300)))
        for _ in 0..<6 { _ = swinging.observe(sample(3200, 2200)); _ = swinging.observe(sample(3300, 2300)) }
        expect(!swinging.observe(sample(3200, 2200)))
        swinging.userRequestedLatest()
        expect(swinging.observe(sample(3300, 2300)))
        swinging.conversationChanged()
        expect(swinging.observe(sample(800, 800)))

        // Lazy layout can report a new maximum on every scroll even though
        // no transcript data changed. Only three scrolls may be issued.
        var progressive = ChatScrollFollowPolicy()
        var progressiveGranted = 0
        for step in 0..<30 {
            let height = 3000.0 + Double(step * 20)
            if progressive.observe(sample(height, height - 1000), contentRevision: 1) {
                progressiveGranted += 1
            }
        }
        expect(progressiveGranted == ChatScrollFollowPolicy.maximumTailScrollsWithoutGrowth)
        // A real streaming update restores the budget even if its geometry
        // is smaller than a previous lazy-layout maximum.
        expect(progressive.observe(sample(3200, 2200), contentRevision: 2))
        expect(progressive.observe(sample(3220, 2220), contentRevision: 3))

        // A real content update cannot pull someone reading earlier text.
        progressive.beginDrag()
        progressive.userDraggedTowardEarlierContent()
        expect(!progressive.observe(sample(3220, 2500), contentRevision: 3))
        progressive.endDrag()
        expect(progressive.settle(expectedRevision: progressive.pendingSettleRevision!))
        expect(!progressive.followsTail)
        expect(!progressive.observe(sample(3300, 2580), contentRevision: 4))
        progressive.userRequestedLatest()
        expect(progressive.observe(sample(3320, 2600), contentRevision: 5))

        // Bounded presentation never changes the archive/session. Walk both
        // directions to prove every absolute message index remains reachable.
        for count in [8, 80, 81, 1998, 2000, 2001, 2002] {
            var page = ChatTranscriptPage()
            func range() -> Range<Int> { page.range(conversationID: "archive", messageCount: count) }
            var visited = Set(range())
            expect(range().count <= 80)
            expect(range().lowerBound % 2 == 0)
            while range().lowerBound > 0 {
                let previousStart = range().lowerBound
                page.navigate(.earlier, conversationID: "archive", messageCount: count)
                expect(range().upperBound == previousStart)
                expect(page.landing(conversationID: "archive") == .end)
                expect(range().count <= 80)
                visited.formUnion(range())
            }
            expect(visited == Set(0..<count))
            page.navigate(.earliest, conversationID: "archive", messageCount: count)
            expect(range().lowerBound == 0)
            expect(page.landing(conversationID: "archive") == .start)
            visited = Set(range())
            while range().upperBound < count {
                let previousEnd = range().upperBound
                page.navigate(.newer, conversationID: "archive", messageCount: count)
                expect(range().lowerBound == previousEnd - previousEnd % 2)
                expect(page.landing(conversationID: "archive") == .start)
                expect(range().count <= 80)
                visited.formUnion(range())
            }
            expect(visited == Set(0..<count))
            page.navigate(.latest, conversationID: "archive", messageCount: count)
            expect(range().upperBound == count)
            expect(range().count <= 80)
            expect(page.landing(conversationID: "archive") == .tail)
        }

        var page = ChatTranscriptPage()
        expect(page.range(conversationID: "a", messageCount: 8) == 0..<8)
        expect(page.range(conversationID: "a", messageCount: 1998) == 1918..<1998)
        expect(page.range(conversationID: "a", messageCount: 1999) == 1920..<1999)
        expect(page.range(conversationID: "a", messageCount: 2000) == 1920..<2000)
        page.pin(conversationID: "a", messageCount: 1999)
        let pinnedBasis = page.basis(conversationID: "a", messageCount: 1999)
        expect(page.range(conversationID: "a", messageCount: 2000) == 1920..<1999)
        expect(page.basis(conversationID: "a", messageCount: 2000) == pinnedBasis)
        page.navigate(.newer, conversationID: "a", messageCount: 2000)
        expect(page.range(conversationID: "a", messageCount: 2000) == 1998..<2000) // no orphan reply
        expect(page.basis(conversationID: "a", messageCount: 2000) != pinnedBasis)
        expect(page.range(conversationID: "b", messageCount: 8) == 0..<8) // another conversation resets the page
        page.navigate(.earliest, conversationID: "a", messageCount: 2000)
        expect(page.range(conversationID: "a", messageCount: 2002) == 0..<80) // new reply does not replace old page
        page.navigate(.latest, conversationID: "a", messageCount: 2002)
        expect(page.range(conversationID: "a", messageCount: 2002) == 1922..<2002)

        var pagedFollow = ChatScrollFollowPolicy()
        expect(pagedFollow.observe(sample(60000, 500), contentRevision: 10))
        pagedFollow.beginDrag()
        pagedFollow.endDrag()
        let staleSettle = pagedFollow.pendingSettleRevision!
        pagedFollow.presentationChanged(to: sample(2500, 2500), followsTail: false)
        expect(!pagedFollow.settle(expectedRevision: staleSettle))
        expect(!pagedFollow.followsTail)
        expect(!pagedFollow.observe(sample(2500, 500), contentRevision: 10))
        expect(!pagedFollow.observe(sample(2700, 700, 350), contentRevision: 11))
        pagedFollow.presentationChanged(to: sample(3000, 3000, 350), followsTail: true)
        expect(pagedFollow.followsTail)
        expect(!pagedFollow.observe(sample(3000, 350, 350), contentRevision: 11))
        expect(pagedFollow.observe(sample(3100, 450, 350), contentRevision: 12))

        print("CHAT_SCROLL_FOLLOW assertions=\(assertions) status=PASS")
    }
}
