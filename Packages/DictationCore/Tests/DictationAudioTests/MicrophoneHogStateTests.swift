import XCTest
@testable import DictationAudio

final class MicrophoneHogStateTests: XCTestCase {
    func testANegativeHogPIDMeansTheDeviceIsFree() {
        XCTAssertEqual(MicrophoneHogState.interpret(hogPID: -1, selfPID: 42), .free)
        XCTAssertEqual(MicrophoneHogState.interpret(hogPID: -50, selfPID: 42), .free)
    }

    func testThisProcessHoggingIsNotAnotherApp() {
        XCTAssertEqual(MicrophoneHogState.interpret(hogPID: 42, selfPID: 42), .thisProcess)
    }

    func testAForeignPIDIsExclusiveAccess() {
        XCTAssertEqual(MicrophoneHogState.interpret(hogPID: 99, selfPID: 42), .otherProcess(99))
    }
}
