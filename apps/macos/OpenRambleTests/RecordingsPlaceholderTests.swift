import DictationCore
import XCTest

final class RecordingsPlaceholderTests: XCTestCase {
    func testAnOrdinaryEndingNeedsNoNote() {
        XCTAssertNil(RecordingsPlaceholder.endNote(for: nil))
        XCTAssertNil(RecordingsPlaceholder.endNote(for: .stoppedByUser))
    }

    func testEveryOtherEndingSaysWhatWasKept() throws {
        for reason in [MeetingEndReason.diskFull, .writeFailed, .crashRecovered] {
            let note = try XCTUnwrap(RecordingsPlaceholder.endNote(for: reason))
            XCTAssertTrue(note.contains("kept"), "\(reason): \(note)")
        }
        XCTAssertNotNil(RecordingsPlaceholder.endNote(for: .applicationQuit))
    }

    func testListeningSaysTheTextWaitsForAPause() {
        XCTAssertEqual(RecordingsPlaceholder.listening.title, "Listening")
        XCTAssertTrue(RecordingsPlaceholder.listening.detail.lowercased().contains("transcript"))
        XCTAssertEqual(TranscriptStatusPolicy.backlogVisibleAfter, 3)
    }

    func testPlaceholdersNeverUseRedLanguageOrBlame() {
        for placeholder in [
            RecordingsPlaceholder.emptyLibrary, .nothingSelected, .notTranscribed, .audioMissing, .recovered,
            .listening, .stillTranscribing, .noSpeech, .transcriptionDidNotFinish, .waitingForModel,
        ] {
            XCTAssertFalse(placeholder.title.isEmpty)
            XCTAssertFalse(placeholder.detail.isEmpty)
            XCTAssertFalse(placeholder.detail.lowercased().contains("error"))
        }
    }

    func testTheDefaultTitleIsTheDate() {
        let date = Date(timeIntervalSince1970: 1_756_900_000)
        XCTAssertEqual(RecordingsPlaceholder.defaultTitle(for: date), date.formatted(date: .abbreviated, time: .shortened))
    }

    func testEveryTranscriptStateHasAPlaceholder() {
        XCTAssertEqual(RecordingsPlaceholder.transcript(for: .live), .stillTranscribing)
        XCTAssertEqual(RecordingsPlaceholder.transcript(for: .complete), .noSpeech)
        XCTAssertEqual(RecordingsPlaceholder.transcript(for: .partial), .transcriptionDidNotFinish)
        XCTAssertEqual(RecordingsPlaceholder.transcript(for: .waitingForModel), .waitingForModel)
        XCTAssertEqual(RecordingsPlaceholder.transcript(for: .none), .notTranscribed)
    }

    func testAOneSidedMeetingCarriesItsNoteAndAVoiceNoteDoesNot() {
        var meeting = MeetingRecordingMetadata(
            startedAt: Date(),
            systemAudio: SystemAudioSummary(wasRequested: true, everDeliveredBuffers: true, everDeliveredAudio: false)
        )
        XCTAssertNotNil(RecordingsPlaceholder.degradedNote(for: meeting))
        meeting.systemAudio.everDeliveredAudio = true
        XCTAssertNil(RecordingsPlaceholder.degradedNote(for: meeting))
        let note = MeetingRecordingMetadata(startedAt: Date(), systemAudio: SystemAudioSummary(wasRequested: false))
        XCTAssertNil(RecordingsPlaceholder.degradedNote(for: note))
    }

    func testAMeetingThatMissedTheMicrophoneCarriesTheInverseNote() {
        let meeting = MeetingRecordingMetadata(
            startedAt: Date(),
            microphoneEverDeliveredAudio: false,
            systemAudio: SystemAudioSummary(wasRequested: true, everDeliveredBuffers: true, everDeliveredAudio: true)
        )
        XCTAssertEqual(
            RecordingsPlaceholder.degradedNote(for: meeting),
            "The other side of this call was recorded. Your microphone was not captured."
        )
        let both = MeetingRecordingMetadata(
            startedAt: Date(),
            microphoneEverDeliveredAudio: false,
            systemAudio: SystemAudioSummary(wasRequested: true, everDeliveredBuffers: true, everDeliveredAudio: false)
        )
        XCTAssertEqual(
            RecordingsPlaceholder.degradedNote(for: both),
            "Neither your microphone nor the other side of this call was captured."
        )
        let voice = MeetingRecordingMetadata(
            startedAt: Date(),
            microphoneEverDeliveredAudio: false,
            systemAudio: SystemAudioSummary(wasRequested: false)
        )
        XCTAssertEqual(RecordingsPlaceholder.degradedNote(for: voice), "Your microphone was not captured.")
        let unknown = MeetingRecordingMetadata(
            startedAt: Date(),
            microphoneEverDeliveredAudio: nil,
            systemAudio: SystemAudioSummary(wasRequested: true, everDeliveredBuffers: true, everDeliveredAudio: true)
        )
        XCTAssertNil(RecordingsPlaceholder.degradedNote(for: unknown), "old files must not look degraded")
    }
}
