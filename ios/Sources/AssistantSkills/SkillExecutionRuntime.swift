import Foundation

/// One plan per runtime. Replace the runtime when input/options change.
/// Call authorize only from an explicit user action after showing that exact step.
/// PDFKit on the device is the only extraction path: like the Play build, there
/// is no original-script service, and no Markdown-to-command interpreter.
public actor SkillExecutionRuntime {
    public nonisolated let plan: SkillExecutionPlan
    private let selection: SkillExecutionSelectedFile
    private let options: SkillExecutionPDFOptions
    private let clock: @Sendable () -> Date
    private var index = 0
    private var grants: [UUID: SkillExecutionApproval] = [:]
    private var bytes: Data?
    private var busy = false
    private var cancelled = false

    public init(selectedFile: SkillExecutionSelectedFile, options: SkillExecutionPDFOptions,
                catalog: BundledSkillCatalog, clock: @escaping @Sendable () -> Date = { Date() }) throws {
        guard let entry = catalog.entry(id: "documents") else { throw SkillCatalogError.notFound }
        self.selection = selectedFile; self.options = options; self.clock = clock
        let provenance = ([entry.original] + entry.assets).map(SkillExecutionProvenance.init)
        let capability = SkillExecutionCapability.nativePDFText
        let detail = "在裝置上以 PDFKit 擷取文字；不會上傳。"
        let steps = [
            SkillExecutionStep(id: UUID(), capability: .selectedPDFRead, title: "讀取選取的 PDF",
                disclosure: "只讀取本次選取的檔案，最多 10 MiB；不會掃描資料夾。",
                availability: SkillExecutionAvailability(capability: .selectedPDFRead, available: true, detail: selectedFile.accessDetail), provenance: provenance),
            SkillExecutionStep(id: UUID(), capability: capability, title: "在裝置上擷取 PDF",
                disclosure: detail,
                availability: SkillExecutionAvailability(capability: capability, available: SkillExecutionPDF.available, detail: detail), provenance: provenance)
        ]
        let id = UUID()
        let filename = String(selectedFile.url.lastPathComponent.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(160))
        let canonical: [String: Any] = ["id": id.uuidString, "selection": selectedFile.id.uuidString,
            "selectionOrigin": selectedFile.browserDownloadID == nil ? "documentPicker" : "browserDownload",
            "downloadID": selectedFile.browserDownloadID?.uuidString ?? "",
            "filename": filename, "pages": options.pages ?? "", "metadata": options.metadataOnly,
            "passwordProvided": options.password != nil, "backend": capability.rawValue,
            "destination": "device",
            "steps": steps.map { ["id": $0.id.uuidString, "capability": $0.capability.rawValue,
                "title": $0.title, "disclosure": $0.disclosure, "available": $0.availability.available,
                "availabilityDetail": $0.availability.detail] as [String: Any] },
            "sources": provenance.map { [$0.repository, $0.path, $0.revision, $0.sha256] }]
        let fingerprint = skillExecutionDigest(try JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys]))
        plan = SkillExecutionPlan(id: id, skillID: entry.id, filename: filename, pages: options.pages,
            metadataOnly: options.metadataOnly, includesPassword: options.password != nil, steps: steps, fingerprint: fingerprint)
    }

    public func nextStep() -> SkillExecutionStep? {
        guard !cancelled, index < plan.steps.count else { return nil }
        return plan.steps[index]
    }

    public func authorize(stepID: UUID) throws -> SkillExecutionApproval {
        guard !cancelled else { throw SkillExecutionError.cancelled }
        guard !busy else { throw SkillExecutionError.busy }
        guard let step = nextStep(), step.id == stepID else { throw SkillExecutionError.stalePlan }
        guard step.availability.available else { throw SkillExecutionError.unavailable }
        let grant = SkillExecutionApproval(id: UUID(), planID: plan.id, stepID: stepID, expiresAt: clock().addingTimeInterval(120))
        grants.removeAll(); grants[grant.id] = grant
        return grant
    }

    public func cancel() {
        cancelled = true; grants.removeAll(); bytes = nil
    }

    public func execute(_ approval: SkillExecutionApproval) async throws -> SkillExecutionStepResult {
        guard !cancelled else { throw SkillExecutionError.cancelled }
        guard !busy else { throw SkillExecutionError.busy }
        guard let issued = grants.removeValue(forKey: approval.id), issued.planID == plan.id,
              issued.stepID == nextStep()?.id else { throw SkillExecutionError.approvalRequired }
        guard clock() < issued.expiresAt else { throw SkillExecutionError.expiredApproval }
        guard let step = nextStep(), step.availability.available else { throw SkillExecutionError.unavailable }
        busy = true
        defer { busy = false }
        do {
            try Task.checkCancellation()
            let result: SkillExecutionStepResult
            if step.capability == .selectedPDFRead {
                let data = try SkillExecutionPDF.read(selection)
                bytes = data
                result = .selectedFileRead(byteCount: data.count, sha256: skillExecutionDigest(data))
            } else {
                guard let data = bytes else { throw SkillExecutionError.stalePlan }
                result = .pdf(try SkillExecutionPDF.extract(data, options: options))
            }
            try Task.checkCancellation()
            guard !cancelled else { throw SkillExecutionError.cancelled }
            index += 1; grants.removeAll()
            if index == plan.steps.count { bytes = nil }
            return result
        } catch is CancellationError {
            cancel(); throw SkillExecutionError.cancelled
        } catch {
            // A failed step needs fresh user approval. Never retry implicitly.
            if cancelled { throw SkillExecutionError.cancelled }
            throw error
        }
    }
}
