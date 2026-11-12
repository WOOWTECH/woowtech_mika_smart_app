import Foundation

/// A reviewed deletion is valid only for the exact installed skill the user
/// saw before opening the confirmation. This carries no execution authority.
public struct SkillDeletionReview: Equatable, Sendable {
    public let skill: PersonalSkill

    public init(skill: PersonalSkill) { self.skill = skill }

    public func apply(to state: inout SkillsState, now: Date = Date()) throws {
        guard state.installed.first(where: { $0.name == skill.name }) == skill else {
            throw SkillsError.changedSinceRead
        }
        try state.remove(name: skill.name, now: now)
    }
}

/// Binds an immediate restore action to the installed value and history record
/// shown by the view. This does not read or persist a shared vault.
public struct SkillRestoreTarget: Equatable, Sendable {
    public let current: PersonalSkill
    public let revision: SkillRevision

    public init?(current: PersonalSkill, revision: SkillRevision) {
        guard revision.name == current.name, revision.previous?.name == current.name else { return nil }
        self.current = current
        self.revision = revision
    }

    @discardableResult
    public func apply(to state: inout SkillsState, availableToolNames: Set<String>,
                      now: Date = Date()) throws -> PersonalSkill {
        guard state.installed.first(where: { $0.name == current.name }) == current,
              state.revisions.reversed().first(where: { $0.name == current.name && $0.canRestore }) == revision else {
            throw SkillsError.changedSinceRead
        }
        return try state.restoreRevision(id: revision.id, expectedCurrentHash: current.fingerprint,
                                         availableToolNames: availableToolNames, now: now)
    }
}
