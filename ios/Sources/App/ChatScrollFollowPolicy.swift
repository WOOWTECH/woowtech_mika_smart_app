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
    static let nearTailDistance = 240.0
    private(set) var followsTail = true
    private var previous: ChatTranscriptViewport?
    private var isDragging = false
    private var isSettling = false
    private var movementRevision = 0

    var pendingSettleRevision: Int? { isSettling ? movementRevision : nil }

    mutating func beginDrag() {
        guard !isDragging else { return }
        isDragging = true
        isSettling = false
        movementRevision += 1
    }

    /// A downward finger drag asks to read earlier content. Disarm immediately
    /// so a streaming delta arriving during the gesture cannot pull the page.
    mutating func userDraggedTowardEarlierContent() { followsTail = false }

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
        followsTail = previous.bottomY - previous.viewportHeight <= Self.nearTailDistance
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
        let viewportChanged = abs(current.viewportHeight - previous.viewportHeight) > 0.5
        if isSettling && (moved || viewportChanged) { movementRevision += 1 }
        if isDragging || isSettling { return false }
        if viewportChanged { return followsTail }
        if moved {
            followsTail = current.bottomY - current.viewportHeight <= Self.nearTailDistance
            return false
        }
        return abs(current.contentHeight - previous.contentHeight) > 0.5 && followsTail
    }

    mutating func conversationChanged() {
        followsTail = true
        previous = nil
        isDragging = false
        isSettling = false
        movementRevision += 1
    }

    mutating func userSubmitted() { conversationChanged() }
}
