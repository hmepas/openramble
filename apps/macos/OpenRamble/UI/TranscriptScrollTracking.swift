import AppKit
import SwiftUI

/// Content growth is not a user scroll. Otherwise each appended paragraph turns following off.
struct TranscriptScrollTracking: ViewModifier {
    let onUserScroll: (CGFloat) -> Void
    @State private var isUserScrolling = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .onScrollPhaseChange { previous, phase, context in
                    isUserScrolling = phase == .interacting || phase == .decelerating
                    let finishedUserScroll = phase == .idle
                        && (previous == .interacting || previous == .decelerating)
                    if isUserScrolling || finishedUserScroll {
                        onUserScroll(max(0, context.geometry.contentSize.height - context.geometry.visibleRect.maxY))
                    }
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
                } action: { _, distance in
                    if isUserScrolling { onUserScroll(distance) }
                }
        } else {
            content.background(LegacyTranscriptScrollObserver(onUserScroll: onUserScroll))
        }
    }
}

/// macOS 14 exposes user scrolling through AppKit instead of SwiftUI's scroll phases.
private struct LegacyTranscriptScrollObserver: NSViewRepresentable {
    let onUserScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ObserverView { ObserverView() }
    func updateNSView(_ view: ObserverView, context: Context) { view.onUserScroll = onUserScroll }
    static func dismantleNSView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: NSView {
        var onUserScroll: ((CGFloat) -> Void)?
        private var observations: [NSObjectProtocol] = []
        private weak var trackedScrollView: NSScrollView?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            // SwiftUI may place the background next to the scroll view rather than inside its clip view.
            let scroll = enclosingScrollView ?? findScrollView(in: superview)
            guard let scroll else { return }
            trackedScrollView = scroll
            for name in [NSScrollView.didLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: scroll, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
        }

        private func findScrollView(in view: NSView?) -> NSScrollView? {
            guard let view else { return nil }
            for child in view.subviews where child !== self {
                if let scroll = child as? NSScrollView,
                   scroll.convert(scroll.bounds, to: self).contains(NSPoint(x: bounds.midX, y: bounds.midY)) {
                    return scroll
                }
                if let scroll = findScrollView(in: child) { return scroll }
            }
            return nil
        }

        private func report() {
            guard let scroll = trackedScrollView, let document = scroll.documentView else { return }
            onUserScroll?(max(0, document.bounds.height - scroll.contentView.bounds.maxY))
        }

        func detach() {
            observations.forEach(NotificationCenter.default.removeObserver)
            observations.removeAll()
            trackedScrollView = nil
        }
    }
}
