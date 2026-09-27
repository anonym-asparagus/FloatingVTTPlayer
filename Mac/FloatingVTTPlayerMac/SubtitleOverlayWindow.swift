import AppKit
import SwiftUI

@MainActor
final class SubtitleOverlayWindow: NSObject, NSWindowDelegate {
    let panel: NSWindow
    private let model: PlayerModel
    private let defaults = UserDefaults.standard
    private var preferredHeight: CGFloat
    private var automaticResize = false
    private var moveStart: (frame: NSRect, pointer: NSPoint)?

    init(model: PlayerModel) {
        self.model = model
        preferredHeight = max(100, CGFloat(UserDefaults.standard.double(forKey: "overlayHeight") == 0
            ? 190 : UserDefaults.standard.double(forKey: "overlayHeight")))
        let frame = Self.restoredFrame(preferredHeight: preferredHeight)
        preferredHeight = frame.height
        panel = InteractiveSubtitleWindow(contentRect: frame,
                                         styleMask: [.borderless],
                                         backing: .buffered, defer: false)
        super.init()
        panel.identifier = NSUserInterfaceItemIdentifier("subtitleOverlay")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications]
        panel.isMovable = false
        let hostingView = NSHostingView(rootView: SubtitleOverlayView(model: model, window: self))
        // The overlay owns its frame. SwiftUI's default size constraints would
        // otherwise shrink or expand this borderless window as the cue changes.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        panel.delegate = self
        updateSubtitleHeight()
    }

    func setVisible(_ visible: Bool) {
        if visible { panel.orderFrontRegardless() }
        else {
            model.overlayHovered = false
            panel.orderOut(nil)
        }
    }

    func refreshHoverState() {
        let hovered = panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
        if model.overlayHovered != hovered { model.overlayHovered = hovered }
    }

    func updateSubtitleHeight() {
        let font = NSFont(name: model.fontFamily, size: model.fontSize)
            ?? NSFont.systemFont(ofSize: model.fontSize, weight: .semibold)
        let text = model.subtitleText.isEmpty ? " " : model.subtitleText
        let width = max(1, panel.frame.width - 44)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        ).height
        let screenHeight = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })?
            .visibleFrame.height ?? .greatestFiniteMagnitude
        let targetHeight = min(screenHeight, max(preferredHeight, ceil(measured) + 110))
        guard abs(panel.frame.height - targetHeight) > 1 else { return }
        var frame = panel.frame
        frame.size.height = targetHeight
        automaticResize = true
        panel.setFrame(frame, display: true)
        automaticResize = false
    }

    func moveWithPointer() {
        guard !model.overlayLocked else { return }
        let pointer = NSEvent.mouseLocation
        guard let moveStart else {
            moveStart = (panel.frame, pointer)
            return
        }
        panel.setFrameOrigin(NSPoint(x: moveStart.frame.minX + pointer.x - moveStart.pointer.x,
                                     y: moveStart.frame.minY + pointer.y - moveStart.pointer.y))
    }

    func endMove() {
        guard moveStart != nil else { return }
        moveStart = nil
        saveFrame()
    }

    func resize(from initialFrame: NSRect, by translation: CGSize) {
        guard !model.overlayLocked else { return }
        let width = max(360, initialFrame.width + translation.width)
        let height = max(100, initialFrame.height + translation.height)
        preferredHeight = height
        var frame = initialFrame
        frame.origin.y = initialFrame.maxY - height
        frame.size = NSSize(width: width, height: height)
        panel.setFrame(frame, display: true)
        defaults.set(Double(preferredHeight), forKey: "overlayHeight")
        updateSubtitleHeight()
    }

    func saveFrame() {
        let frame = panel.frame
        defaults.set(Double(frame.minX), forKey: "overlayX")
        defaults.set(Double(frame.minY), forKey: "overlayY")
        defaults.set(Double(frame.width), forKey: "overlayWidth")
        defaults.set(Double(preferredHeight), forKey: "overlayHeight")
    }

    func windowDidMove(_ notification: Notification) {
        if moveStart == nil { saveFrame() }
    }
    func windowDidResize(_ notification: Notification) {
        if !automaticResize { saveFrame() }
    }

    private static func restoredFrame(preferredHeight: CGFloat) -> NSRect {
        let store = UserDefaults.standard
        let requestedWidth = max(360, CGFloat(store.double(forKey: "overlayWidth") == 0
            ? 1000 : store.double(forKey: "overlayWidth")))
        let x = CGFloat(store.double(forKey: "overlayX"))
        let y = CGFloat(store.double(forKey: "overlayY"))
        let saved = NSRect(x: x, y: y, width: requestedWidth, height: preferredHeight)
        if store.object(forKey: "overlayX") != nil {
            let bestScreen = NSScreen.screens.max {
                $0.visibleFrame.intersection(saved).area < $1.visibleFrame.intersection(saved).area
            }
            if let visible = bestScreen?.visibleFrame,
               visible.intersection(saved).area >= 160 * 80 {
                let width = min(requestedWidth, visible.width)
                let height = min(preferredHeight, visible.height)
                return NSRect(x: min(max(x, visible.minX), visible.maxX - width),
                              y: min(max(y, visible.minY), visible.maxY - height),
                              width: width, height: height)
            }
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(requestedWidth, screen.width)
        return NSRect(x: screen.midX - width / 2, y: screen.minY + 70,
                      width: width, height: min(preferredHeight, screen.height - 70))
    }
}

private extension NSRect {
    var area: CGFloat { max(0, width) * max(0, height) }
}

private final class InteractiveSubtitleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
