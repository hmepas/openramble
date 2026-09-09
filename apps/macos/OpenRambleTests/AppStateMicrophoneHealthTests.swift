import DictationAudio
import DictationCore
import XCTest

/// The microphone can fail the same way the tap does: start succeeds, zeros
/// arrive, the file grows. The honesty strip, the badge, and the filed note
/// have to say so — otherwise a meeting of only others looks healthy.
@MainActor
final class AppStateMicrophoneHealthTests: XCTestCase {
    private var harness: AppHarness!

    private func makeHarness() throws -> AppHarness {
        let harness = try AppHarness()
        harness.permissions.microphoneGranted = true
        self.harness = harness
        return harness
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now > deadline {
                XCTFail("timed out waiting", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func testASilentMicrophoneIsSaidOutLoudMarkedAndRecovered() async throws {
        let harness = try makeHarness()
        defer { harness.tearDown() }
        harness.defaults.set(true, forKey: AppState.systemAudioIntroShownKey)
        harness.meetingCapture.microphoneHealth = MeetingCapture.ChannelHealth(
            everDeliveredBuffers: true, everDeliveredAudio: false, lastBlockAt: .now
        )
        harness.meetingCapture.systemHealth = MeetingCapture.ChannelHealth(
            everDeliveredBuffers: true, everDeliveredAudio: true, lastBlockAt: .now, lastAudibleAt: .now
        )
        let state = harness.makeState()
        guard state.systemAudioMode == .enabled else { throw XCTSkip("this Mac cannot record what it plays") }

        state.startRecording()
        try await waitUntil { state.meetingState == .recording }
        XCTAssertEqual(state.liveMicrophoneHealth, .verifying)
        try await waitUntil({ state.liveMicrophoneHealth.marksRecordingDegraded }, timeout: .seconds(6))
        if case .unheard = state.liveMicrophoneHealth {} else {
            XCTFail("expected unheard, got \(state.liveMicrophoneHealth)")
        }
        XCTAssertTrue(
            harness.announcer.messages.contains("Your microphone is not being captured."),
            "got \(harness.announcer.messages)"
        )
        XCTAssertGreaterThanOrEqual(harness.meetingCapture.recoverCount, 1)

        state.stopRecording()
        try await waitUntil { state.meetingState == .idle && !state.recordings.isEmpty }
        let filed = try XCTUnwrap(state.recordings.first)
        XCTAssertEqual(filed.microphoneEverDeliveredAudio, false)
        XCTAssertEqual(
            RecordingsPlaceholder.degradedNote(for: filed),
            "The other side of this call was recorded. Your microphone was not captured."
        )
        XCTAssertEqual(state.liveMicrophoneHealth, .idle)
    }
}
