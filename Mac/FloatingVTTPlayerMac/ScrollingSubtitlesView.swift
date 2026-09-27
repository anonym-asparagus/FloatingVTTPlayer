import SwiftUI

struct ScrollingSubtitlesView: View {
    @ObservedObject var model: PlayerModel
    let onBack: () -> Void

    private var scrollTarget: Int? {
        guard !model.subtitleCues.isEmpty else { return nil }
        if let activeCueIndex = model.activeCueIndex { return activeCueIndex }
        return model.subtitleCues.firstIndex { $0.start > model.currentTime }
            ?? model.subtitleCues.indices.last
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PlayerPalette.background,
                         PlayerPalette.subtitlesGlow,
                         PlayerPalette.background],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 48) {
                artworkColumn
                    .frame(width: 230)
                subtitleColumn
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 58)
            .padding(.top, 72)
            .padding(.bottom, 16)

            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .background(PlayerPalette.raised.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Return to previous page")
                    .accessibilityLabel("Return to previous page")
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 116)
            .padding(.trailing, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var artworkColumn: some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.28, blue: 0.60),
                                                 Color(red: 0.07, green: 0.10, blue: 0.26)],
                                         startPoint: .top, endPoint: .bottom))
                Circle()
                    .fill(Color(red: 0.91, green: 0.89, blue: 1).opacity(0.85))
                    .frame(width: 47, height: 47)
                    .blur(radius: 1)
                    .offset(x: 25, y: -42)
                Ellipse()
                    .fill(Color(red: 0.10, green: 0.22, blue: 0.49))
                    .frame(width: 290, height: 100)
                    .offset(x: -40, y: 70)
                Ellipse()
                    .fill(Color(red: 0.08, green: 0.16, blue: 0.36))
                    .frame(width: 310, height: 90)
                    .offset(x: 75, y: 95)
                Image(systemName: "waveform")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .offset(y: 72)
            }
            .frame(width: 230, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .stroke(.white.opacity(0.13), lineWidth: 1))

            Text(model.currentTrack?.audioURL.deletingPathExtension().lastPathComponent
                 ?? "Nothing playing")
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.middle)
            Text(model.currentTrack == nil ? "Local audio" : "Local audio · VTT synced")
                .font(.system(size: 12))
                .foregroundStyle(PlayerPalette.secondary)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var subtitleColumn: some View {
        if model.subtitleCues.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "text.aligncenter")
                    .font(.system(size: 34, weight: .ultraLight))
                Text(model.currentTrack == nil
                     ? "Play a track to see scrolling subtitles"
                     : "No VTT subtitles for this track")
                    .font(.system(size: 17))
            }
            .foregroundStyle(PlayerPalette.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Text("SYNCED SUBTITLES")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(PlayerPalette.secondary)
                    .padding(.bottom, 12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 28) {
                            ForEach(model.subtitleCues.indices, id: \.self) { index in
                                subtitleLine(at: index)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 150)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { scroll(to: scrollTarget, using: proxy, animated: false) }
                    .onChange(of: scrollTarget) { _, target in
                        scroll(to: target, using: proxy, animated: true)
                    }
                    .onChange(of: model.currentTrack?.audioURL) { _, _ in
                        scroll(to: scrollTarget, using: proxy, animated: false)
                    }
                }
            }
        }
    }

    private func subtitleLine(at index: Int) -> some View {
        let cue = model.subtitleCues[index]
        let isCurrent = model.activeCueIndex == index
        return Button { model.seek(to: cue.start) } label: {
            Text(cue.text)
                .font(.system(size: isCurrent ? 29 : 25,
                              weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(isCurrent ? 1 : 0.46))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Seek to subtitle: \(cue.text)")
    }

    private func scroll(to index: Int?, using proxy: ScrollViewProxy, animated: Bool) {
        guard let index else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(index, anchor: .center)
            }
        } else {
            proxy.scrollTo(index, anchor: .center)
        }
    }
}
