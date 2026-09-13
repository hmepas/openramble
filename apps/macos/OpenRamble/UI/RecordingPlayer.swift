import AVFoundation
import Foundation

/// Streams the original recording through a mono mixer. The file separates
/// microphone and system audio for recognition, not for left and right ears.
@MainActor
final class RecordingPlayer: ObservableObject {
    @Published private(set) var loadedID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var failedToLoad = false

    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let monoMixer = AVAudioMixerNode()
    private var file: AVAudioFile?
    private var startFrame: AVAudioFramePosition = 0
    private var scheduleID = UUID()
    private var tick: Timer?
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    static let skipInterval: TimeInterval = 15

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(player)
        engine.attach(monoMixer)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
    }

    /// Loading the same recording does not reset its position. AVAudioFile
    /// reads only the header here; even a long meeting starts without making
    /// another file or loading the recording into memory.
    func load(id: UUID, url: URL?) {
        guard loadedID != id else { return }
        unload()
        loadedID = id
        guard let url, let file = try? AVAudioFile(forReading: url), file.length > 0,
              let mono = AVAudioFormat(standardFormatWithSampleRate: file.processingFormat.sampleRate, channels: 1)
        else {
            failedToLoad = true
            return
        }
        self.file = file
        engine.connect(player, to: monoMixer, format: file.processingFormat)
        engine.connect(monoMixer, to: engine.mainMixerNode, format: mono)
        // Core Audio uses equal-power gains when downmixing stereo. Leave
        // enough headroom for two simultaneous full-scale voices.
        monoMixer.outputVolume = file.processingFormat.channelCount == 2 ? sqrt(0.5) : 1
        // Leave the main mixer's output format to macOS so it follows a
        // change between speakers and headphones.
        duration = Double(file.length) / file.processingFormat.sampleRate
        schedule(from: 0)
    }

    func unload() {
        stopTicking()
        scheduleID = UUID()
        player.stop()
        engine.stop()
        file = nil
        loadedID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        failedToLoad = false
    }

    func toggle() {
        guard file != nil else { return }
        if isPlaying {
            pause()
        } else {
            if currentTime >= duration - 0.05 { schedule(from: 0) }
            play()
        }
    }

    func pause() {
        guard isPlaying else { return }
        updateTime()
        player.pause()
        engine.pause()
        isPlaying = false
        stopTicking()
    }

    func seek(to time: TimeInterval) {
        guard file != nil else { return }
        let resume = isPlaying
        schedule(from: time)
        isPlaying = false
        stopTicking()
        if resume, currentTime < duration { play() }
        else { engine.pause() }
    }

    func skip(by seconds: TimeInterval) {
        if isPlaying { updateTime() }
        seek(to: currentTime + seconds)
    }

    private func play() {
        do {
            if !engine.isRunning { try engine.start() }
            player.play()
            failedToLoad = false
            isPlaying = true
            startTicking()
        } catch {
            failedToLoad = true
            isPlaying = false
            stopTicking()
        }
    }

    private func schedule(from time: TimeInterval) {
        guard let file else { return }
        let id = UUID()
        scheduleID = id
        player.stop()
        startFrame = AVAudioFramePosition(max(0, min(duration, time)) * file.processingFormat.sampleRate)
        currentTime = Double(startFrame) / file.processingFormat.sampleRate
        let remaining = file.length - startFrame
        guard remaining > 0 else { return }
        player.scheduleSegment(
            file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining),
            at: nil, completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Stop, seek and loading another file also complete an old
                // schedule. Only the one still playing may finish the UI.
                guard let self, self.scheduleID == id else { return }
                self.currentTime = self.duration
                self.isPlaying = false
                self.stopTicking()
                self.engine.pause()
            }
        }
    }

    private func updateTime() {
        guard let file, let renderTime = player.lastRenderTime,
              let time = player.playerTime(forNodeTime: renderTime) else { return }
        currentTime = min(duration, Double(startFrame) / file.processingFormat.sampleRate
            + Double(time.sampleTime) / time.sampleRate)
    }

    private func outputChanged() {
        guard file != nil else { return }
        let resume = isPlaying
        // Configuration changes stop the engine and clear scheduled audio.
        // Restore the schedule even while paused so the next Play has audio.
        schedule(from: currentTime)
        if resume { play() }
    }

    private func startTicking() {
        stopTicking()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateTime() }
        }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    private func stopTicking() {
        tick?.invalidate()
        tick = nil
    }
}
