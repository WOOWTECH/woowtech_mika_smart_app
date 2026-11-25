import AssistantDocuments
import AssistantModels
import AssistantSkills
import Foundation

/// The device side of file_create: AssistantDocuments' writers and the
/// export's PDF renderer, writing into the created-files folder
/// (ChatCreatedFileStore). Nothing here saves, shares or sends a file; the
/// person does that from the file's card.
enum ChatFileCreation {
    static func tool(store: ChatCreatedFileStore) -> ChatFileTool {
        ChatFileTool(offer: DocumentCreationPrompts.offer, inStep: DocumentCreationPrompts.inStep, accepts: { accepts($0) },
                     limitResult: DocumentCreationResult.refused("file_limit",
                        "No file was made: one request makes at most \(ChatCreatedFileLimits.maximumPerRequest) files. Tell the user which files are ready."),
                     make: { command, earlier, language in await make(command, earlier: earlier, language: language, store: store) })
    }

    /// A reply asking for file_create, with each top-level key once, as the
    /// chat's other commands. Its arguments are checked when it runs.
    static func accepts(_ text: String) -> Bool {
        DocumentCreationCommand.isCommand(text) && (try? RawCommandEnvelope.fields(in: ChatSkillCommand.unfenced(text))) != nil
    }

    static func make(_ command: String, earlier: [String: URL], language: String,
                     store: ChatCreatedFileStore) async -> ChatFileToolOutcome {
        // Off the main actor: a long PDF takes seconds to draw.
        await Task.detached(priority: .userInitiated) {
            let parsed: DocumentCreationCommand
            do { parsed = try DocumentCreationCommand.parse(command) }
            catch { return .failed(result: DocumentCreationResult.failed(error)) }
            // A name the conversation already has gets a number, so the cards and a ZIP tell them apart.
            let name = DocumentFileName.unique(parsed.fileName, taken: Set(earlier.keys.map { $0.lowercased() }))
            do {
                let data = try DocumentCreation.make(parsed, language: language,
                    pdf: { try DocumentPDFRenderer.render($0, marks: .boldItalicCode) },
                    file: { earlier[$0].flatMap { try? Data(contentsOf: $0) } })
                let file = try store.save(data, name: name, format: parsed.format.rawValue)
                return .created(file, result: DocumentCreationResult.created(fileName: name, format: parsed.format, bytes: data.count))
            } catch ChatCreatedFileError.storageFull {
                return .failed(result: DocumentCreationResult.refused("storage_full",
                    "No file was made: the app's space for files waiting to be saved or shared is full. Ask the user to save, share or remove earlier files first."))
            } catch let error as DocumentPDFError {
                return .failed(result: DocumentCreationResult.failed(error == .pageLimitExceeded ? "too_large" : "pdf_failed",
                    error == .pageLimitExceeded ? "No file was made: a PDF has at most \(DocumentPDFRenderer.maximumPages) pages. Make it shorter or split it."
                        : "No file was made: the PDF could not be drawn. Try a docx instead."))
            } catch {
                return .failed(result: DocumentCreationResult.failed(error))
            }
        }.value
    }
}
