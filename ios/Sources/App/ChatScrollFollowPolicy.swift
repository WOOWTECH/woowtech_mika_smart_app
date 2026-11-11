import Foundation

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
    private var deliberatelyReadingEarlier = false
    private var draggedTowardEarlier = false
    private var draggedTowardLatest = false
    private var dragStartOffset: Double?
    private var movementRevision = 0

    var pendingSettleRevision: Int? { isSettling ? movementRevision : nil }
    var needsTailScroll: Bool {
        guard followsTail, !isDragging, !isSettling, let previous, previous.isValid else { return false }
        return previous.bottomY - previous.viewportHeight > Self.tailArrivalTolerance
    }

    mutating func beginDrag() {
        guard !isDragging else { return }
        isDragging = true
        isSettling = false
        draggedTowardEarlier = false
        draggedTowardLatest = false
        dragStartOffset = previous.map { $0.contentHeight - $0.bottomY }
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
        movementRevision += 1
    }

    @discardableResult
    mutating func settle(expectedRevision: Int) -> Bool {
        guard isSettling, !isDragging, movementRevision == expectedRevision else { return false }
        isSettling = false
        defer {
            dragStartOffset = nil
            draggedTowardEarlier = false
            draggedTowardLatest = false
        }
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
        deliberatelyReadingEarlier = false
        followsTail = true
        isDragging = false
        isSettling = false
        dragStartOffset = nil
        draggedTowardEarlier = false
        draggedTowardLatest = false
        movementRevision += 1
    }

    /// Returns whether the caller should scroll to the transcript's tail.
    mutating func observe(_ current: ChatTranscriptViewport) -> Bool {
        guard current.isValid else { return false }
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
        isDragging = false
        isSettling = false
        deliberatelyReadingEarlier = false
        draggedTowardEarlier = false
        draggedTowardLatest = false
        dragStartOffset = nil
        movementRevision += 1
    }

    mutating func userSubmitted() { conversationChanged() }
}
