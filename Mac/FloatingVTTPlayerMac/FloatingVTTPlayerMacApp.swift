import AppKit
import SwiftUI

@main
struct FloatingVTTPlayerMacApp: App {
    @StateObject private var model = PlayerModel()

    var body: some Scene {
        Window("Floating VTT Player", id: "player") {
            PlayerView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Playback") {
                Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
                Button("Previous Track") { model.playPrevious() }
                Button("Next Track") { model.playNext() }
            }
        }

        MenuBarExtra("Floating VTT Player", systemImage: "captions.bubble") {
            PlayerMenu(model: model)
        }
    }
}

struct PlayerWindowConfiguration: NSViewRepresentable {
    let onSpace: () -> Void

    func makeNSView(context: Context) -> PlayerWindowObserver {
        let view = PlayerWindowObserver()
        view.onSpace = onSpace
        return view
    }

    func updateNSView(_ view: PlayerWindowObserver, context: Context) {
        view.onSpace = onSpace
    }
}

final class PlayerWindowObserver: NSView {
    var onSpace: (() -> Void)?
    private var keyMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window,
                  event.window === window, window.isKeyWindow,
                  event.keyCode == 49,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            else { return event }
            if window.firstResponder is NSTextView { return event }
            if !event.isARepeat { self.onSpace?() }
            return nil
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}
