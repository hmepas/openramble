import DictationCore
import XCTest

final class RecordingsPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3 * 3_600)!
        return calendar
    }

    private func recording(_ date: String) -> MeetingRecordingMetadata {
        MeetingRecordingMetadata(
            startedAt: ISO8601DateFormatter().date(from: date)!,
            systemAudio: SystemAudioSummary(wasRequested: true)
        )
    }

    func testLibraryGroupsByLocalDayAndKeepsNewestFirst() {
        let beforeMidnight = recording("2026-09-10T20:59:00Z")
        let afterMidnight = recording("2026-09-10T21:01:00Z")
        let later = recording("2026-09-11T09:00:00Z")
        let groups = RecordingDayGroup.make([beforeMidnight, later, afterMidnight], calendar: calendar)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.recordings.map(\.id), [later.id, afterMidnight.id])
        XCTAssertEqual(groups.last?.recordings.map(\.id), [beforeMidnight.id])
    }

    func testSecondsDisambiguateOnlyMatchingMinutes() {
        let first = recording("2026-09-10T12:31:05Z")
        let second = recording("2026-09-10T12:31:49Z")
        let third = recording("2026-09-10T12:32:00Z")
        let group = RecordingDayGroup(day: calendar.startOfDay(for: first.startedAt), recordings: [first, second, third])
        XCTAssertTrue(group.needsSeconds(for: first, calendar: calendar))
        XCTAssertTrue(group.needsSeconds(for: second, calendar: calendar))
        XCTAssertFalse(group.needsSeconds(for: third, calendar: calendar))
    }

    func testChannelHeadingsGroupWithoutMergingOrLosingParagraphs() {
        let first = MeetingUtterance(channel: .system, start: 0, end: 2, text: "First")
        let second = MeetingUtterance(channel: .system, start: 2, end: 4, text: "Second")
        let you = MeetingUtterance(channel: .microphone, start: 4, end: 5, text: "Yes")
        let failed = MeetingUtterance(channel: .system, start: 5, end: 6, text: "", isFailed: true)
        let sections = TranscriptSection.make([failed, second, you, first])
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.first?.utterances, [first, second])
        XCTAssertEqual(sections.flatMap(\.utterances), [first, second, you, failed])
        var revised = second
        revised.text = "Second, continued"
        XCTAssertEqual(TranscriptSection.make([first, revised]).first?.id, sections.first?.id)
        XCTAssertTrue(TranscriptSection.make([]).isEmpty)
    }

    func testFollowingYieldsToReadingAndResumesOnlyAtTheBottom() {
        var state = TranscriptFollowState()
        XCTAssertTrue(state.followsLatest)
        state.userScrolled(distanceFromBottom: 120)
        XCTAssertFalse(state.followsLatest)
        state.userScrolled(distanceFromBottom: 25)
        XCTAssertFalse(state.followsLatest)
        state.userScrolled(distanceFromBottom: 20)
        XCTAssertTrue(state.followsLatest)
        state.userScrolled(distanceFromBottom: 200)
        state.returnToLatest()
        XCTAssertTrue(state.followsLatest)
    }
}
