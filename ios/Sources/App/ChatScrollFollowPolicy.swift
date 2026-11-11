import Foundation

/// Geometry is measured in the transcript ScrollView's visible coordinate space.
/// Content growth is not evidence that the reader scrolled; only a change in
/// position with stable content and viewport dimensions is.
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

    /// A downward finger drag asks to read earlier content. Disarm immediately
    /// so a streaming delta arriving during the gesture cannot pull the page.
    mutating func userDraggedTowardEarlierContent() { followsTail = false }

    /// Returns whether the caller should scroll to the transcript's tail.
    mutating func observe(_ current: ChatTranscriptViewport) -> Bool {
        guard current.isValid else { return false }
        defer { previous = current }
        guard let previous else { return followsTail }
        let resized = abs(current.contentHeight - previous.contentHeight) > 0.5
            || abs(current.viewportHeight - previous.viewportHeight) > 0.5
        if resized { return followsTail }
        if abs(current.bottomY - previous.bottomY) > 0.5 {
            followsTail = current.bottomY - current.viewportHeight <= Self.nearTailDistance
        }
        return false
    }

    mutating func conversationChanged() {
        followsTail = true
        previous = nil
    }
}
