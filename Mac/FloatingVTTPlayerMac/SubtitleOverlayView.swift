import AppKit
import SwiftUI

struct SubtitleOverlayView: View {
    @ObservedObject var model: PlayerModel
    let window: SubtitleOverlayWindow
    @State private var appearanceOpen = false
    @State private var resizeStart: NSRect?

    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.72, green: 0.74, blue: 0.78)
                .opacity(!model.overlayLocked && model.overlayHovered ? 0.26 : 0.001)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { _ in window.moveWithPointer() }
                    .onEnded { _ in window.endMove() })

            VStack(spacing: 8) {
                toolbar
                    .opacity(model.overlayHovered ? 1 : 0)
                    .allowsHitTesting(model.overlayHovered)
                Spacer(minLength: 0)
                Text(model.subtitleText)
                    .font(model.fontFamily == ".AppleSystemUIFont"
                          ? .system(size: model.fontSize, weight: .semibold)
                          : .custom(model.fontFamily, size: model.fontSize))
                    .foregroundStyle(model.subtitleColor)
                    .shadow(color: .black.opacity(model.shadowOpacity), radius: 8, x: 0, y: 3)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(model.subtitleText.isEmpty ? "No subtitle" : model.subtitleText)
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.overlayLocked {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if resizeStart == nil { resizeStart = window.panel.frame }
                            if let resizeStart { window.resize(from: resizeStart, by: value.translation) }
                        }
                        .onEnded { _ in resizeStart = nil; window.saveFrame() })
                    .padding(5)
                    .help("Drag to resize subtitles")
                    .opacity(model.overlayHovered ? 1 : 0)
                    .allowsHitTesting(model.overlayHovered)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(model.overlayHovered && !model.overlayLocked
                    ? Color(red: 0.61, green: 0.62, blue: 1).opacity(0.8)
                    : .clear, lineWidth: 1)
            .allowsHitTesting(false))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.14), value: model.overlayHovered)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { model.togglePlayback() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .help(model.isPlaying ? "Pause" : "Play")

            Button { model.overlayLocked.toggle() } label: {
                Image(systemName: model.overlayLocked ? "lock.fill" : "lock.open.fill")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .help(model.overlayLocked ? "Unlock subtitle position" : "Lock subtitle position")

            if !model.overlayLocked {
                Button { appearanceOpen.toggle() } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                    .help("Subtitle appearance")
                    .accessibilityLabel("Subtitle appearance")
                    .accessibilityValue(appearanceOpen ? "Open" : "Closed")
                    .popover(isPresented: $appearanceOpen, arrowEdge: .bottom) { appearanceControls }
            }

            Button { model.hideOverlay() } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
                .help("Hide subtitles")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(red: 0.08, green: 0.09, blue: 0.14).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 9))
    }
    private var appearanceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subtitle appearance").font(.headline)
            Picker("Font", selection: $model.fontFamily) {
                Text("System").tag(".AppleSystemUIFont")
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .frame(width: 250)
            HStack {
                Text("Size")
                Slider(value: $model.fontSize, in: 18...120, step: 1)
                Text("\(Int(model.fontSize))").monospacedDigit()
            }
            ColorPicker("Text color", selection: $model.subtitleColor, supportsOpacity: true)
            HStack {
                Text("Shadow")
                Slider(value: $model.shadowOpacity, in: 0...1)
            }
        }
        .padding(16)
        .frame(width: 310)
        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.20))
        .background(Color.white)
        .preferredColorScheme(.light)
    }
}
