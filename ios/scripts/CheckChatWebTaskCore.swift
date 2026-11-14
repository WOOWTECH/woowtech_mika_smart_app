import Foundation

/// Runs ChatWebTaskChecks outside XCTest; prints the assertion count as JSON.
@main struct CheckChatWebTaskCore {
    @MainActor static func main() async {
        do {
            let count = try await ChatWebTaskChecks.run()
            print(#"{"assertions": \#(count)}"#)
        } catch {
            print("FAIL chat web task: \(error)")
            exit(1)
        }
    }
}
