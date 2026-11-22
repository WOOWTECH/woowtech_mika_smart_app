import Foundation

/// Presentation only. The session/archive retain every entry and its absolute index.
/// Completed turns are user/assistant pairs; an in-flight user occupies the last slot.
struct ChatTranscriptPage: Equatable {
    static let maximumMessages = 80
    enum Destination: Equatable { case earliest, earlier, newer, latest }
    enum Landing: Equatable { case start, end, tail }

    private var conversationID: String?
    private var pinnedRange: Range<Int>?
    private var revision = 0
    private var requestedLanding = Landing.tail

    func range(conversationID: String, messageCount: Int) -> Range<Int> {
        let count = max(0, messageCount)
        if self.conversationID == conversationID, let pinnedRange {
            return min(pinnedRange.lowerBound, count)..<min(pinnedRange.upperBound, count)
        }
        // Round up to a user boundary. 79 entries + one streaming reply still fit
        // the 80-message window; completion restores 40 full turns.
        let lower = max(0, count - Self.maximumMessages)
        return (lower + lower % 2)..<count
    }

    func basis(conversationID: String, messageCount: Int) -> ChatTranscriptPageBasis {
        ChatTranscriptPageBasis(conversationID: conversationID,
                                firstIndex: range(conversationID: conversationID, messageCount: messageCount).lowerBound,
                                requestRevision: self.conversationID == conversationID ? revision : 0)
    }

    func landing(conversationID: String) -> Landing {
        self.conversationID == conversationID ? requestedLanding : .tail
    }

    mutating func pin(conversationID: String, messageCount: Int) {
        let current = range(conversationID: conversationID, messageCount: messageCount)
        if self.conversationID != conversationID { revision = 0; requestedLanding = .tail }
        self.conversationID = conversationID
        pinnedRange = current
    }

    mutating func trackLatest(conversationID: String) {
        if self.conversationID != conversationID { revision = 0; requestedLanding = .tail }
        self.conversationID = conversationID
        pinnedRange = nil
    }

    mutating func navigate(_ destination: Destination, conversationID: String, messageCount: Int) {
        let current = range(conversationID: conversationID, messageCount: messageCount)
        let count = max(0, messageCount)
        self.conversationID = conversationID
        switch destination {
        case .earliest:
            pinnedRange = 0..<min(Self.maximumMessages, count)
            requestedLanding = .start
        case .earlier:
            guard current.lowerBound > 0 else { return }
            pinnedRange = max(0, current.lowerBound - Self.maximumMessages)..<current.lowerBound
            requestedLanding = .end
        case .newer:
            guard current.upperBound < count else { return }
            // A pinned page can end in the formerly in-flight user. Include that
            // user again with its now-completed reply, never an orphan answer.
            let lower = current.upperBound - current.upperBound % 2
            pinnedRange = lower..<min(lower + Self.maximumMessages, count)
            requestedLanding = .start
        case .latest:
            pinnedRange = nil
            requestedLanding = .tail
        }
        revision += 1
    }
}

/// Only a changed origin or an explicit navigation changes the geometry basis.
/// Ordinary appends/streaming on the same page keep the existing follow policy.
struct ChatTranscriptPageBasis: Equatable {
    let conversationID: String
    let firstIndex: Int
    let requestRevision: Int
}

/// Geometry is measured in the transcript ScrollView's visible coordinate space.
/// Content growth and a reader's movement can happen in the same layout pass.
/// The content's offset from the visible origin separates those two changes.
struct ChatTranscriptViewport: Equatable {
    let contentHeight: Double
    let bottomY: Double
    let viewportHeight: Double

    var isValid: Bool {
        contentHeight.isFinite && bottomY.isFinite && viewportHeight.isFinite
            && contentHeight >= 0 && viewportHeight > 0
    }
}

struct ChatScrollFollowPolicy {
    /// Layout can differ by a few points at the physical end of a ScrollView.
    /// This is an end-of-content tolerance, not a reading-distance threshold.
    static let tailArrivalTolerance = 12.0
    private static let actualScrollTolerance = 2.0
    private(set) var followsTail = true
    private var previous: ChatTranscriptViewport?
    private var isDragging = false
    private var isSettling = false
    private var layoutSettling = false
    private var deliberatelyReadingEarlier = false
    private var draggedTowardEarlier = false
    private var draggedTowardLatest = false
    private var dragStartOffset: Double?
    private var movementRevision = 0
    /// Tail scrolls granted since the content last grew past its tallest
    /// height. A scroll can make lazy rows measure again and change the very
    /// geometry it reacts to; without new content a few scrolls are enough,
    /// and more wait for new content or the person.
    private var tailScrollsWithoutGrowth = 0
    private var tallestContent = 0.0
    private var contentRevision: UInt64?
    static let maximumTailScrollsWithoutGrowth = 3

    var pendingSettleRevision: Int? { isSettling ? movementRevision : nil }
    /// Recheck when consuming a queued scroll: a drag may have started since it was requested.
    var canScrollToTail: Bool { followsTail && !isDragging && !isSettling }
    var needsTailScroll: Bool {
        guard canScrollToTail, let previous, previous.isValid else { return false }
        return previous.bottomY - previous.viewportHeight > Self.tailArrivalTolerance
    }

    /// A known keyboard/composer change can move the content origin without
    /// reader input. Keep the current follow intent until geometry is quiet;
    /// never replace a drag, its deceleration, or an existing reading hold.
    mutating func beginLayoutTransition() {
        guard followsTail, !deliberatelyReadingEarlier, !isDragging,
              !isSettling || layoutSettling else { return }
        isSettling = true
        layoutSettling = true
        movementRevision += 1
    }

    mutating func beginDrag() {
        guard !isDragging else { return }
        tailScrollsWithoutGrowth = 0
        // A drag that starts before the previous one settled continues it: two
        // quick flicks back to the end are one move toward the latest text, even
        // when the second only bounces at the end.
        if !isSettling || layoutSettling {
            draggedTowardEarlier = false
            draggedTowardLatest = false
            dragStartOffset = previous.map { $0.contentHeight - $0.bottomY }
        }
        isDragging = true
        isSettling = false
        layoutSettling = false
        movementRevision += 1
    }

    /// Finger direction alone is not a scroll: short content can bounce at the
    /// bottom without changing its final offset. Drag/settle suppresses jumps
    /// until actual displacement can be measured.
    mutating func userDraggedTowardEarlierContent() { draggedTowardEarlier = true }

    /// Moving back toward the latest text only restores follow after the
    /// gesture ends, deceleration settles, and the actual bottom is reached.
    mutating func userDraggedTowardLatestContent() { draggedTowardLatest = true }

    /// SwiftUI's drag end precedes scroll deceleration. The caller must wait
    /// for a quiet geometry interval before passing the captured revision to
    /// settle; a later movement invalidates that revision.
    mutating func endDrag() {
        guard isDragging else { return }
        isDragging = false
        isSettling = true
        layoutSettling = false
        movementRevision += 1
    }

    @discardableResult
    mutating func settle(expectedRevision: Int) -> Bool {
        guard isSettling, !isDragging, movementRevision == expectedRevision else { return false }
        isSettling = false
        defer {
            layoutSettling = false
            dragStartOffset = nil
            draggedTowardEarlier = false
            draggedTowardLatest = false
        }
        if layoutSettling { return true }
        guard let previous, previous.isValid else { return true }
        let atBottom = previous.bottomY - previous.viewportHeight <= Self.tailArrivalTolerance
        // contentHeight - bottomY is the content's offset from the viewport
        // origin; growth alone changes both terms equally. Compare the final
        // position with the drag start, after deceleration/bounce has settled.
        let currentOffset = previous.contentHeight - previous.bottomY
        let movedEarlier = (dragStartOffset ?? currentOffset) - currentOffset
        if deliberatelyReadingEarlier {
            if draggedTowardLatest && movedEarlier < -Self.actualScrollTolerance && atBottom {
                deliberatelyReadingEarlier = false
                followsTail = true
            } else {
                followsTail = false
            }
        } else if draggedTowardEarlier && movedEarlier > Self.actualScrollTolerance && !atBottom {
            deliberatelyReadingEarlier = true
            followsTail = false
        }
        return true
    }

    /// An explicit, accessible request also works when the platform scrolls
    /// without reporting a SwiftUI DragGesture (for example, VoiceOver).
    mutating func userRequestedLatest() {
        tailScrollsWithoutGrowth = 0
        deliberatelyReadingEarlier = false
        followsTail = true
        isDragging = false
        isSettling = false
        layoutSettling = false
        dragStartOffset = nil
        draggedTowardEarlier = false
        draggedTowardLatest = false
        movementRevision += 1
    }

    /// Returns whether the caller should scroll to the transcript's tail.
    mutating func observe(_ current: ChatTranscriptViewport, hasTranscript: Bool = true) -> Bool {
        let wanted = wantsTailScroll(current, hasTranscript: hasTranscript)
        guard hasTranscript, current.isValid else { return wanted }
        if current.contentHeight > tallestContent + Self.tailArrivalTolerance {
            tallestContent = current.contentHeight
            tailScrollsWithoutGrowth = 0
        }
        guard wanted, tailScrollsWithoutGrowth < Self.maximumTailScrollsWithoutGrowth else { return false }
        tailScrollsWithoutGrowth += 1
        return true
    }

    /// A content revision is supplied by the transcript model, not geometry.
    /// Layout remeasurement cannot renew the budget, even if every measured
    /// height exceeds the previous maximum.
    mutating func observe(_ current: ChatTranscriptViewport, contentRevision: UInt64,
                          hasTranscript: Bool = true) -> Bool {
        let wanted = wantsTailScroll(current, hasTranscript: hasTranscript)
        guard hasTranscript, current.isValid else { return false }
        if self.contentRevision != contentRevision {
            self.contentRevision = contentRevision
            tailScrollsWithoutGrowth = 0
        }
        guard wanted, tailScrollsWithoutGrowth < Self.maximumTailScrollsWithoutGrowth else { return false }
        tailScrollsWithoutGrowth += 1
        return true
    }

    private mutating func wantsTailScroll(_ current: ChatTranscriptViewport, hasTranscript: Bool) -> Bool {
        // Empty-state examples are browsed independently of transcript follow.
        // Do not record their geometry: the first real message starts fresh.
        guard hasTranscript, current.isValid else { return false }
        defer { previous = current }
        guard let previous else { return followsTail && !isDragging && !isSettling }
        let oldOffset = previous.contentHeight - previous.bottomY
        let newOffset = current.contentHeight - current.bottomY
        let moved = abs(newOffset - oldOffset) > 0.5
        let contentChanged = abs(current.contentHeight - previous.contentHeight) > 0.5
        let viewportChanged = abs(current.viewportHeight - previous.viewportHeight) > 0.5
        if isSettling && (moved || viewportChanged) { movementRevision += 1 }
        if isDragging || isSettling { return false }
        // Subtracting bottomY from contentHeight cancels growth that occurs in
        // the same layout pass. A smaller offset means the visible origin moved
        // toward earlier content, even if the transcript also grew. Never let
        // that update issue a tail scroll; geometry cannot prove whether the
        // movement came from touch, accessibility scrolling, or layout.
        let movedEarlier = oldOffset - newOffset > Self.actualScrollTolerance
        let awayFromBottom = current.bottomY - current.viewportHeight > Self.tailArrivalTolerance
        if movedEarlier && awayFromBottom {
            deliberatelyReadingEarlier = true
            followsTail = false
            return false
        }
        if viewportChanged { return followsTail }
        if moved && !contentChanged {
            // Passive motion toward the bottom does not prove intent to resume
            // following; the explicit button remains available while held.
            return false
        }
        return contentChanged && followsTail
    }

    mutating func conversationChanged() {
        followsTail = true
        previous = nil
        tallestContent = 0
        contentRevision = nil
        tailScrollsWithoutGrowth = 0
        isDragging = false
        isSettling = false
        layoutSettling = false
        deliberatelyReadingEarlier = false
        draggedTowardEarlier = false
        draggedTowardLatest = false
        dragStartOffset = nil
        movementRevision += 1
    }

    mutating func userSubmitted() { conversationChanged() }

    /// A different page has unrelated content-height/offset coordinates. Called
    /// once, only after geometry stamped with that page's basis arrives. This is
    /// not a content update and must not compare against the previous page.
    mutating func presentationChanged(to position: ChatTranscriptViewport?, followsTail: Bool) {
        conversationChanged()
        self.followsTail = followsTail
        deliberatelyReadingEarlier = !followsTail
        previous = position.flatMap { $0.isValid ? $0 : nil }
    }
}
