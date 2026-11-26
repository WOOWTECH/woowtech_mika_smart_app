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
        expect(follow.canScrollToTail)

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

        // Native 281, 11:20:47: keyboard/composer layout moved bottomY from
        // 532 to 716 with height 42822 and viewport 528 unchanged. Later the
        // viewport shrank to 187. A declared layout transition preserves follow.
        var keyboardLayout = ChatScrollFollowPolicy()
        keyboardLayout.presentationChanged(to: sample(42822, 588, 584), followsTail: true)
        keyboardLayout.beginLayoutTransition()
        let firstLayoutRevision = keyboardLayout.pendingSettleRevision!
        for position in [sample(42822, 588, 528), sample(42822, 532, 528)] {
            expect(!keyboardLayout.observe(position, contentRevision: 4))
            expect(keyboardLayout.followsTail)
        }
        let beforeKeyboardEvent = keyboardLayout.pendingSettleRevision!
        keyboardLayout.beginLayoutTransition() // keyboard follows the focus/Done change
        expect(keyboardLayout.pendingSettleRevision != beforeKeyboardEvent)
        for position in [sample(42822, 532, 494), sample(42822, 532, 528),
                         sample(42822, 716, 528), sample(42822, 716, 481),
                         sample(42822, 485, 481), sample(42822, 485, 187),
                         sample(42822, 712, 187)] {
            expect(!keyboardLayout.observe(position, contentRevision: 4))
            expect(keyboardLayout.followsTail)
            expect(!keyboardLayout.needsTailScroll)
            expect(!keyboardLayout.canScrollToTail)
        }
        expect(!keyboardLayout.settle(expectedRevision: firstLayoutRevision))
        expect(!keyboardLayout.settle(expectedRevision: beforeKeyboardEvent))
        let duringKeyboardLayout = keyboardLayout
        expect(keyboardLayout.settle(expectedRevision: keyboardLayout.pendingSettleRevision!))
        expect(keyboardLayout.pendingSettleRevision == nil)
        expect(keyboardLayout.followsTail)
        expect(keyboardLayout.canScrollToTail)
        expect(keyboardLayout.needsTailScroll)
        expect(!keyboardLayout.observe(sample(42822, 191, 187), contentRevision: 4)) // catch-up reaches tail
        expect(!keyboardLayout.needsTailScroll)
        // Once layout settles, unannounced platform scrolling still holds.
        expect(!keyboardLayout.observe(sample(42822, 311, 187), contentRevision: 4))
        expect(!keyboardLayout.followsTail)
        keyboardLayout.beginLayoutTransition()
        expect(keyboardLayout.pendingSettleRevision == nil)
        expect(!keyboardLayout.observe(sample(42822, 311, 528), contentRevision: 4))
        expect(!keyboardLayout.followsTail)
        expect(!keyboardLayout.needsTailScroll)
        expect(!keyboardLayout.canScrollToTail)

        // Pure streaming growth keeps the content-origin offset fixed. It must
        // neither restart the layout quiet timer nor bypass it on a new revision.
        var streamingLayout = ChatScrollFollowPolicy()
        streamingLayout.presentationChanged(to: sample(1200, 500), followsTail: true)
        streamingLayout.beginLayoutTransition()
        let streamingLayoutRevision = streamingLayout.pendingSettleRevision!
        for step in 1...6 {
            let growth = Double(step * 20)
            expect(!streamingLayout.observe(sample(1200 + growth, 500 + growth), contentRevision: UInt64(step)))
            expect(streamingLayout.pendingSettleRevision == streamingLayoutRevision)
            expect(streamingLayout.followsTail)
            expect(!streamingLayout.canScrollToTail)
        }
        // The original timer can catch up while the reply is still streaming.
        expect(streamingLayout.settle(expectedRevision: streamingLayoutRevision))
        expect(streamingLayout.canScrollToTail)
        expect(streamingLayout.needsTailScroll)
        expect(!streamingLayout.observe(sample(1320, 500), contentRevision: 6))
        expect(!streamingLayout.needsTailScroll)
        expect(streamingLayout.observe(sample(1340, 520), contentRevision: 7))
        expect(streamingLayout.followsTail)

        // A real drag takes its baseline AFTER the keyboard's displacement.
        // A no-op gesture must not inherit that displacement; a subsequent
        // actual 20 pt move must hold, even if keyboard events keep arriving.
        var layoutNoOpDrag = duringKeyboardLayout
        layoutNoOpDrag.beginDrag()
        expect(!layoutNoOpDrag.canScrollToTail)
        layoutNoOpDrag.userDraggedTowardEarlierContent()
        layoutNoOpDrag.endDrag()
        expect(!layoutNoOpDrag.canScrollToTail)
        expect(layoutNoOpDrag.settle(expectedRevision: layoutNoOpDrag.pendingSettleRevision!))
        expect(layoutNoOpDrag.followsTail)
        expect(layoutNoOpDrag.canScrollToTail)
        // A tail request queued by settle must not survive a new drag before consumption.
        layoutNoOpDrag.beginDrag()
        expect(!layoutNoOpDrag.canScrollToTail)
        var layoutReader = duringKeyboardLayout
        let interruptedLayoutRevision = layoutReader.pendingSettleRevision!
        layoutReader.beginDrag()
        layoutReader.userDraggedTowardEarlierContent()
        layoutReader.beginLayoutTransition() // active drag has priority
        expect(layoutReader.pendingSettleRevision == nil)
        expect(!layoutReader.settle(expectedRevision: interruptedLayoutRevision))
        expect(!layoutReader.observe(sample(42822, 732, 187), contentRevision: 4))
        layoutReader.endDrag()
        let readerSettleRevision = layoutReader.pendingSettleRevision!
        layoutReader.beginLayoutTransition() // reader deceleration also has priority
        expect(layoutReader.pendingSettleRevision == readerSettleRevision)
        expect(layoutReader.settle(expectedRevision: readerSettleRevision))
        expect(!layoutReader.followsTail)
        expect(!layoutReader.canScrollToTail)
        layoutReader.beginLayoutTransition()
        expect(layoutReader.pendingSettleRevision == nil)
        expect(!layoutReader.needsTailScroll)

        // Explicit navigation/reset cancels old layout timers and suppression.
        var resetLayout = duringKeyboardLayout
        let resetLayoutRevision = resetLayout.pendingSettleRevision!
        resetLayout.userRequestedLatest()
        expect(resetLayout.pendingSettleRevision == nil)
        expect(!resetLayout.settle(expectedRevision: resetLayoutRevision))
        expect(!resetLayout.observe(sample(42822, 732, 187), contentRevision: 4))
        expect(!resetLayout.followsTail)
        resetLayout = duringKeyboardLayout
        resetLayout.conversationChanged()
        expect(resetLayout.pendingSettleRevision == nil)
        expect(!resetLayout.settle(expectedRevision: resetLayoutRevision))
        expect(resetLayout.observe(sample(300, 300), contentRevision: 0))

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
        // Repeated known layout events invalidate timers, not the scroll budget.
        var layoutBudget = progressive
        for step in 0..<6 {
            let height = 3600.0 + Double(step * 20)
            layoutBudget.beginLayoutTransition()
            let oldLayoutRevision = layoutBudget.pendingSettleRevision!
            layoutBudget.beginLayoutTransition()
            expect(!layoutBudget.settle(expectedRevision: oldLayoutRevision))
            let beforeGrowth = layoutBudget.pendingSettleRevision!
            expect(!layoutBudget.observe(sample(height, height - 1000), contentRevision: 1))
            expect(layoutBudget.pendingSettleRevision == beforeGrowth) // pure growth does not restart the timer
            expect(layoutBudget.settle(expectedRevision: beforeGrowth))
            expect(layoutBudget.followsTail)
            expect(!layoutBudget.observe(sample(height + 1, height - 999), contentRevision: 1))
        }
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

        // A created file's card is part of its reply's row, not an entry, so the session counts it
        // as transcript content of its own (ChatSession.createdFiles). That is the model's word,
        // never a measurement: each kind of change moves the revision.
        var revision = ChatTranscriptRevision()
        let unchanged = revision.value
        revision.entriesChanged()
        let afterReply = revision.value
        revision.replyPreviewChanged()
        let afterPreview = revision.value
        revision.createdFilesChanged()
        expect(Set([unchanged, afterReply, afterPreview, revision.value]).count == 4)

        // 11/25 simulator run: in a long chat the reply's text showed and its file card stayed under
        // the composer. Layout passes (lazy rows measuring again after each tail scroll) can use up
        // the tail-scroll budget before the card's height arrives, or long before it changes.
        // The budget's last scrolls: each is granted and followed by a small remeasure, then the next is refused.
        func spendScrolls(_ policy: inout ChatScrollFollowPolicy, _ revision: ChatTranscriptRevision,
                          height start: Double, scrolls: Int) -> Double {
            var height = start
            for _ in 0..<scrolls {
                height += 4
                expect(policy.observe(sample(height, 504), contentRevision: revision.value))
                expect(!policy.observe(sample(height, 500), contentRevision: revision.value))
            }
            height += 4
            expect(!policy.observe(sample(height, 504), contentRevision: revision.value)) // the budget is spent
            return height
        }
        func longChatAfterReply() -> (ChatScrollFollowPolicy, ChatTranscriptRevision) {
            var policy = ChatScrollFollowPolicy()
            var revision = ChatTranscriptRevision()
            policy.presentationChanged(to: sample(9000, 500), followsTail: true)
            revision.entriesChanged() // the reply grows the content: a scroll to the tail
            expect(policy.observe(sample(9120, 620), contentRevision: revision.value))
            expect(!policy.observe(sample(9120, 500), contentRevision: revision.value)) // it landed
            expect(spendScrolls(&policy, revision, height: 9120, scrolls: 2) == 9132)
            expect(policy.followsTail)
            return (policy, revision)
        }
        // Following: the card arrives, and the chat goes on to the end, with the card above the composer.
        var (followsCard, followsCardRevision) = longChatAfterReply()
        followsCardRevision.createdFilesChanged()
        expect(followsCard.observe(sample(9242, 614), contentRevision: followsCardRevision.value)) // +110
        expect(!followsCard.observe(sample(9242, 500), contentRevision: followsCardRevision.value)) // landed
        expect(followsCard.followsTail && !followsCard.needsTailScroll)
        // The card's own remeasures spend the budget. Later it turns into "Removed" and shrinks by 60:
        // still the end of the chat, with no blank under it.
        let cardHeight = spendScrolls(&followsCard, followsCardRevision, height: 9242, scrolls: 2)
        followsCardRevision.createdFilesChanged()
        expect(followsCard.observe(sample(cardHeight - 60, 444), contentRevision: followsCardRevision.value))
        expect(!followsCard.observe(sample(cardHeight - 60, 500), contentRevision: followsCardRevision.value))
        expect(followsCard.followsTail && !followsCard.needsTailScroll)
        // A reader who scrolled up on purpose is not pulled down by a card that arrives or changes.
        var (readsCard, readsCardRevision) = longChatAfterReply()
        readsCard.beginDrag()
        readsCard.userDraggedTowardEarlierContent()
        expect(!readsCard.observe(sample(9132, 804), contentRevision: readsCardRevision.value)) // 300 points up
        readsCard.endDrag()
        expect(readsCard.settle(expectedRevision: readsCard.pendingSettleRevision!))
        expect(!readsCard.followsTail)
        readsCardRevision.createdFilesChanged()
        expect(!readsCard.observe(sample(9242, 914), contentRevision: readsCardRevision.value)) // the card arrives below
        expect(!readsCard.followsTail && !readsCard.needsTailScroll && !readsCard.canScrollToTail)
        readsCardRevision.createdFilesChanged()
        expect(!readsCard.observe(sample(9182, 854), contentRevision: readsCardRevision.value)) // "Removed"
        expect(!readsCard.followsTail && !readsCard.needsTailScroll && !readsCard.canScrollToTail)
        readsCard.beginLayoutTransition() // a header row coming or going does not hold or pull them either
        expect(readsCard.pendingSettleRevision == nil && !readsCard.followsTail)
        expect(!readsCard.observe(sample(9182, 854, 466), contentRevision: readsCardRevision.value))
        expect(!readsCard.followsTail && !readsCard.needsTailScroll)

        // Modeled on the same run (the numbers are illustrative): a header row (a step line, a
        // receipt, a note) came above a long chat pinned to its tail, the viewport shrank 34 points
        // and the content slid 22 points toward the earlier text. Geometry alone reads that as the
        // reader scrolling away, as it did for the keyboard in native 281, and the reply and its
        // card stay under 回到最新訊息. The view declares such a change like the composer's, and the
        // chat goes on to the end once the layout is quiet.
        var headerUndeclared = ChatScrollFollowPolicy()
        headerUndeclared.presentationChanged(to: sample(9000, 500), followsTail: true)
        expect(!headerUndeclared.observe(sample(9000, 522, 466), contentRevision: 1))
        expect(!headerUndeclared.followsTail)
        var headerDeclared = ChatScrollFollowPolicy()
        headerDeclared.presentationChanged(to: sample(9000, 500), followsTail: true)
        headerDeclared.beginLayoutTransition()
        expect(!headerDeclared.observe(sample(9000, 522, 466), contentRevision: 1))
        expect(headerDeclared.followsTail)
        expect(!headerDeclared.observe(sample(9160, 682, 466), contentRevision: 2)) // the reply and its card
        expect(!headerDeclared.observe(sample(9160, 700, 500), contentRevision: 2)) // the row goes
        expect(headerDeclared.followsTail && !headerDeclared.canScrollToTail)
        expect(headerDeclared.settle(expectedRevision: headerDeclared.pendingSettleRevision!))
        expect(headerDeclared.followsTail && headerDeclared.needsTailScroll) // the catch-up brings the card up
        expect(!headerDeclared.observe(sample(9160, 500), contentRevision: 2))
        expect(headerDeclared.followsTail && !headerDeclared.needsTailScroll)

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
