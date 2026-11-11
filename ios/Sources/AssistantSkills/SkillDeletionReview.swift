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
