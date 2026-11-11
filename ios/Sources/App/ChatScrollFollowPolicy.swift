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
    private(set) var followsTail = true
    private var previous: ChatTranscriptViewport?
    private var isDragging = false
    private var isSettling = false
    private var deliberatelyReadingEarlier = false
    private var draggedTowardLatest = false
    private var movementRevision = 0

    var pendingSettleRevision: Int? { isSettling ? movementRevision : nil }

    mutating func beginDrag() {
        guard !isDragging else { return }
        isDragging = true
        isSettling = false
        draggedTowardLatest = false
        movementRevision += 1
    }

    /// A downward finger drag asks to read earlier content. Disarm immediately
    /// so a streaming delta arriving during the gesture cannot pull the page.
    mutating func userDraggedTowardEarlierContent() {
        deliberatelyReadingEarlier = true
        followsTail = false
    }

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
        guard isSettling, !isDragging, movementRevision == expectedRevision,
              let previous, previous.isValid else { return false }
        isSettling = false
        let atBottom = previous.bottomY - previous.viewportHeight <= Self.tailArrivalTolerance
        if deliberatelyReadingEarlier {
            if draggedTowardLatest && atBottom {
                deliberatelyReadingEarlier = false
                followsTail = true
            } else {
                followsTail = false
            }
        } else {
            followsTail = atBottom
            deliberatelyReadingEarlier = !atBottom
        }
        return true
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
        if viewportChanged { return followsTail }
        if moved && !contentChanged {
            // Geometry alone can move to the bottom during a keyboard/layout
            // update. It cannot prove that the reader chose to resume follow.
            if !deliberatelyReadingEarlier &&
                current.bottomY - current.viewportHeight > Self.tailArrivalTolerance {
                deliberatelyReadingEarlier = true
                followsTail = false
            }
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
        draggedTowardLatest = false
        movementRevision += 1
    }

    mutating func userSubmitted() { conversationChanged() }
}
