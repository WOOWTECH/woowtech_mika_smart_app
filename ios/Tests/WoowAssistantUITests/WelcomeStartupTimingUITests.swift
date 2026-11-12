import XCTest

/// Screenshots and AX checks are diagnostic observations of an isolated DEBUG
/// fixture. They cannot certify the timing or appearance of a Release build.
final class WelcomeStartupTimingUITests: XCTestCase {
    func testIsolatedColdLaunchWelcomeTimeline() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This diagnostic uses only an isolated simulator fixture")
        #else
        continueAfterFailure = false
        executionTimeAllowance = 180
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode", "-UITestNamespace", UUID().uuidString, "-WelcomeStartupTiming"]
        defer { app.terminate() }
        let start = ProcessInfo.processInfo.systemUptime
        app.launch()
        let launchReturned = ProcessInfo.processInfo.systemUptime - start
        print("WELCOME_UI launch_return_ms=\(Int(launchReturned * 1000))")
        let example = app.buttons["chat.emptyExample.web"].firstMatch
        var lastExists = false, lastHittable = false
        for target in [0.0, 3.0, 10.0, 20.0, 55.0] {
            let remaining = target - (ProcessInfo.processInfo.systemUptime - start)
            if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
            let beforeScreenshot = ProcessInfo.processInfo.systemUptime
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "welcome-\(Int(target))-seconds"
            shot.lifetime = .keepAlways
            add(shot)
            let beforeQuery = ProcessInfo.processInfo.systemUptime
            let header = app.buttons["chat.menu"].firstMatch.exists
            let composer = app.descendants(matching: .any).matching(identifier: "chat.draft").firstMatch.exists
            lastExists = example.exists
            lastHittable = example.isHittable
            let afterQuery = ProcessInfo.processInfo.systemUptime
            print("WELCOME_UI target_s=\(Int(target)) capture_start_ms=\(Int((beforeScreenshot-start)*1000)) " +
                  "capture_duration_ms=\(Int((beforeQuery-beforeScreenshot)*1000)) " +
                  "query_duration_ms=\(Int((afterQuery-beforeQuery)*1000)) " +
                  "header=\(header) composer=\(composer) example_exists=\(lastExists) example_hittable=\(lastHittable)")
        }
        XCTAssertTrue(lastExists && lastHittable, "Inspect the retained synthetic screenshots and event timing on failure")
        #endif
    }
}
