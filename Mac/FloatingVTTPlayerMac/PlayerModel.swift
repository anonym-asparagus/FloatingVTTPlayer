import AppKit
import AVFoundation
import SwiftUI

private final class AudioFinishDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in self?.onFinish?() }
    }
}

struct LibraryFolder: Identifiable {
    let id: String
    let url: URL
    let bookmark: Data
    let addedAt: Date
    let accessGranted: Bool
    var displayName: String
    var tracks: [AudioTrack]
    var isAvailable: Bool

    var name: String { displayName }
    var subtitleCount: Int { tracks.filter(\.hasSubtitle).count }
}

struct UserPlaylist: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var trackPaths: [String]
}

enum LibrarySelection: Equatable {
    case allFiles
    case recentlyAdded
    case favorites
    case playlist(UUID)
}

private struct SavedFolder: Codable {
    let path: String
    let bookmark: Data
    let addedAt: Date
    let displayName: String?
}

@MainActor
final class PlayerModel: ObservableObject {
    @Published private(set) var folders: [LibraryFolder] = []
    @Published private(set) var selection: LibrarySelection = .allFiles
    @Published private(set) var selectedFolderID: String?
    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var favoritePaths: Set<String> = []
    @Published private(set) var currentTrack: AudioTrack?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var subtitleText = ""
    @Published private(set) var subtitleCues: [SubtitleCue] = []
    @Published private(set) var activeCueIndex: Int?
    @Published var errorMessage: String?

    @Published var volume: Double {
        didSet {
            let normalized = min(1, max(0, volume))
            player?.volume = Float(normalized)
            defaults.set(normalized, forKey: "volume")
        }
    }
    @Published var fontSize: Double {
        didSet {
            defaults.set(min(120, max(18, fontSize)), forKey: "fontSize")
            overlay?.updateSubtitleHeight()
        }
    }
    @Published var fontFamily: String {
        didSet {
            defaults.set(fontFamily, forKey: "fontFamily")
            overlay?.updateSubtitleHeight()
        }
    }
    @Published var subtitleColor: Color {
        didSet {
            defaults.set(NSColor(subtitleColor).usingColorSpace(.deviceRGB)?.hexString ?? "#FFFFFF",
                         forKey: "subtitleColor")
        }
    }
    @Published var shadowOpacity: Double {
        didSet { defaults.set(shadowOpacity, forKey: "shadowOpacity") }
    }
    @Published var overlayLocked: Bool {
        didSet { defaults.set(overlayLocked, forKey: "overlayLocked") }
    }
    @Published var overlayVisible = false {
        didSet { overlay?.setVisible(overlayVisible) }
    }
    @Published var overlayHovered = false

    private let defaults = UserDefaults.standard
    private let audioFinishDelegate = AudioFinishDelegate()
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var playbackQueue: [AudioTrack] = []
    private var trackAddedAt: [String: Date] = [:]
    private var overlay: SubtitleOverlayWindow?

    init() {
        let store = UserDefaults.standard
        volume = store.object(forKey: "volume") as? Double ?? 0.8
        fontSize = store.object(forKey: "fontSize") as? Double ?? 22
        fontFamily = store.string(forKey: "fontFamily") ?? ".AppleSystemUIFont"
        subtitleColor = Color(NSColor(hex: store.string(forKey: "subtitleColor") ?? "#FFFFFF") ?? .white)
        shadowOpacity = store.object(forKey: "shadowOpacity") as? Double ?? 1
        overlayLocked = store.object(forKey: "overlayLocked") as? Bool ?? false
        favoritePaths = Set(store.stringArray(forKey: "favoriteTrackPaths") ?? [])
        if let data = store.data(forKey: "userPlaylists"),
           let saved = try? JSONDecoder().decode([UserPlaylist].self, from: data) {
            playlists = saved
        }
        if let data = store.data(forKey: "trackAddedAt"),
           let saved = try? JSONDecoder().decode([String: Date].self, from: data) {
            trackAddedAt = saved
        }

        audioFinishDelegate.onFinish = { [weak self] in self?.playNext() }
        let refreshTimer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPlaybackTime()
                self?.overlay?.refreshHoverState()
            }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
        restoreLibrary()
    }

    var allTracks: [AudioTrack] { folders.flatMap(\.tracks) }
    var selectedFolder: LibraryFolder? {
        guard let selectedFolderID else { return nil }
        return folders.first { $0.id == selectedFolderID }
    }
    var visibleTracks: [AudioTrack] {
        switch selection {
        case .allFiles:
            return selectedFolder?.tracks ?? []
        case .recentlyAdded:
            return allTracks.sorted {
                let left = trackAddedAt[$0.audioURL.path] ?? .distantPast
                let right = trackAddedAt[$1.audioURL.path] ?? .distantPast
                if left != right { return left > right }
                return $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
        case .favorites:
            return allTracks.filter { favoritePaths.contains($0.audioURL.path) }
        case .playlist(let id):
            guard let playlist = playlists.first(where: { $0.id == id }) else { return [] }
            let byPath = Dictionary(uniqueKeysWithValues: allTracks.map { ($0.audioURL.path, $0) })
            return playlist.trackPaths.compactMap { byPath[$0] }
        }
    }

    func searchFilenames(_ query: String) -> [AudioTrack] {
        FilenameSearch.rank(allTracks, matching: query)
    }

    func folderContaining(_ track: AudioTrack) -> LibraryFolder? {
        folders.first { folder in folder.tracks.contains(track) }
    }

    func selectAllFiles() {
        selection = .allFiles
        selectedFolderID = nil
    }

    func selectFolder(_ id: String) {
        guard folders.contains(where: { $0.id == id }) else { return }
        selection = .allFiles
        selectedFolderID = id
        rescanFolder(id)
    }

    func selectRecentlyAdded() {
        selection = .recentlyAdded
        selectedFolderID = nil
    }

    func selectFavorites() {
        selection = .favorites
        selectedFolderID = nil
    }

    func selectPlaylist(_ id: UUID) {
        guard playlists.contains(where: { $0.id == id }) else { return }
        selection = .playlist(id)
        selectedFolderID = nil
    }

    func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Add audio folders"
        panel.message = "Import folders containing MP3/WAV audio and matching VTT subtitles."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        if let selectedFolder { panel.directoryURL = selectedFolder.url }
        guard panel.runModal() == .OK else { return }
        var lastAddedID: String?
        for url in panel.urls {
            do {
                lastAddedID = try addFolder(url)
            } catch {
                errorMessage = "Could not add \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if let lastAddedID { selectFolder(lastAddedID) }
    }

    @discardableResult
    private func addFolder(_ url: URL) throws -> String {
        let canonical = url.standardizedFileURL
        let id = canonical.path
        if folders.contains(where: { $0.id == id }) { return id }
        let accessGranted = canonical.startAccessingSecurityScopedResource()
        do {
            let bookmark = try canonical.bookmarkData(options: .withSecurityScope,
                                                      includingResourceValuesForKeys: nil, relativeTo: nil)
            let tracks = try scanFolder(canonical)
            let addedAt = Date()
            folders.append(LibraryFolder(id: id, url: canonical, bookmark: bookmark,
                                         addedAt: addedAt, accessGranted: accessGranted,
                                         displayName: canonical.lastPathComponent,
                                         tracks: tracks, isAvailable: true))
            recordNewTracks(tracks, at: addedAt)
            saveFolders()
            return id
        } catch {
            if accessGranted { canonical.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    func removeFolder(_ id: String) {
        removeFolders([id])
    }

    func removeFolders(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let removed = folders.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        if let currentTrack, removed.contains(where: { $0.tracks.contains(currentTrack) }) {
            stopPlayback()
        }
        for folder in removed where folder.accessGranted {
            folder.url.stopAccessingSecurityScopedResource()
        }
        folders.removeAll { ids.contains($0.id) }
        if let selectedFolderID, ids.contains(selectedFolderID) { self.selectedFolderID = nil }
        saveFolders()
    }

    func renameFolder(_ id: String, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].displayName = name
        saveFolders()
    }

    private func restoreLibrary() {
        let saved: [SavedFolder]
        if let data = defaults.data(forKey: "libraryFolders"),
           let decoded = try? JSONDecoder().decode([SavedFolder].self, from: data) {
            saved = decoded
        } else if let oldBookmark = defaults.data(forKey: "folderBookmark") {
            saved = [SavedFolder(path: "", bookmark: oldBookmark, addedAt: Date(), displayName: nil)]
        } else {
            return
        }
        var restored: [LibraryFolder] = []
        for item in saved {
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: item.bookmark, options: .withSecurityScope,
                                    relativeTo: nil, bookmarkDataIsStale: &stale)
            guard let url = resolved ?? (item.path.isEmpty ? nil : URL(fileURLWithPath: item.path)) else {
                continue
            }
            let canonical = url.standardizedFileURL
            let accessGranted = canonical.startAccessingSecurityScopedResource()
            let tracks = (try? scanFolder(canonical)) ?? []
            let available = (try? FileManager.default.attributesOfItem(atPath: canonical.path)) != nil
            let bookmark = stale
                ? ((try? canonical.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil)) ?? item.bookmark)
                : item.bookmark
            restored.append(LibraryFolder(id: canonical.path, url: canonical, bookmark: bookmark,
                                          addedAt: item.addedAt, accessGranted: accessGranted,
                                          displayName: item.displayName ?? canonical.lastPathComponent,
                                          tracks: tracks, isAvailable: available))
            recordNewTracks(tracks, at: item.addedAt)
        }
        folders = restored
        saveFolders()
    }

    private func rescanFolder(_ id: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        do {
            let tracks = try scanFolder(folders[index].url)
            folders[index].tracks = tracks
            folders[index].isAvailable = true
            recordNewTracks(tracks, at: Date())
        } catch {
            folders[index].isAvailable = false
            errorMessage = "Could not read \(folders[index].name): \(error.localizedDescription)"
        }
    }

    private func scanFolder(_ url: URL) throws -> [AudioTrack] {
        let contents = try FileManager.default.contentsOfDirectory(at: url,
            includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        let audio = contents.filter { ["mp3", "wav"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let subtitles = contents.filter { $0.pathExtension.lowercased() == "vtt" }
        var used = Set<URL>()
        return audio.map { file in
            let subtitle = SubtitleMatcher.findBestMatch(for: file, in: subtitles, excluding: used)
            if let subtitle { used.insert(subtitle) }
            return AudioTrack(audioURL: file, subtitleURL: subtitle)
        }
    }

    private func saveFolders() {
        let items = folders.map {
            SavedFolder(path: $0.url.path, bookmark: $0.bookmark, addedAt: $0.addedAt,
                        displayName: $0.displayName)
        }
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: "libraryFolders") }
    }

    private func recordNewTracks(_ tracks: [AudioTrack], at date: Date) {
        var changed = false
        for track in tracks where trackAddedAt[track.audioURL.path] == nil {
            trackAddedAt[track.audioURL.path] = date
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(trackAddedAt) {
            defaults.set(data, forKey: "trackAddedAt")
        }
    }

    func isFavorite(_ track: AudioTrack) -> Bool {
        favoritePaths.contains(track.audioURL.path)
    }

    func toggleFavorite(_ track: AudioTrack) {
        let path = track.audioURL.path
        if !favoritePaths.insert(path).inserted { favoritePaths.remove(path) }
        defaults.set(Array(favoritePaths), forKey: "favoriteTrackPaths")
    }

    func createPlaylist(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let playlist = UserPlaylist(id: UUID(), name: name, trackPaths: [])
        playlists.append(playlist)
        savePlaylists()
        selectPlaylist(playlist.id)
    }

    func renamePlaylist(_ id: UUID, to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = name
        savePlaylists()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        if selection == .playlist(id) { selectAllFiles() }
        savePlaylists()
    }

    func addTrack(_ track: AudioTrack, toPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        let path = track.audioURL.path
        guard !playlists[index].trackPaths.contains(path) else { return }
        playlists[index].trackPaths.append(path)
        savePlaylists()
    }

    func removeTrack(_ track: AudioTrack, fromPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].trackPaths.removeAll { $0 == track.audioURL.path }
        savePlaylists()
    }

    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) { defaults.set(data, forKey: "userPlaylists") }
    }

    func startOverlay() {
        guard overlay == nil else { return }
        overlay = SubtitleOverlayWindow(model: self)
        overlay?.setVisible(overlayVisible)
    }

    func hideOverlay() { overlayVisible = false }

    func playTrack(_ track: AudioTrack, in queue: [AudioTrack]) {
        do {
            let newCues = try track.subtitleURL.map(WebVTTParser.parseFile) ?? []
            let newPlayer = try AVAudioPlayer(contentsOf: track.audioURL)
            newPlayer.delegate = audioFinishDelegate
            newPlayer.volume = Float(volume)
            newPlayer.prepareToPlay()
            player?.stop()
            player = newPlayer
            subtitleCues = newCues
            activeCueIndex = nil
            playbackQueue = queue.isEmpty ? [track] : queue
            currentTrack = track
            currentTime = 0
            duration = newPlayer.duration
            setSubtitle("")
            isPlaying = newPlayer.play()
            if isPlaying { overlayVisible = true }
            refreshPlaybackTime()
        } catch {
            errorMessage = "Could not play \(track.fileName): \(error.localizedDescription)"
        }
    }

    func togglePlayback() {
        guard let player else {
            if let first = visibleTracks.first { playTrack(first, in: visibleTracks) }
            return
        }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            isPlaying = player.play()
        }
        refreshPlaybackTime()
    }

    func playPrevious() {
        guard !playbackQueue.isEmpty else { return }
        let index = playbackQueue.firstIndex(where: { $0.audioURL == currentTrack?.audioURL }) ?? 0
        playTrack(playbackQueue[(index - 1 + playbackQueue.count) % playbackQueue.count], in: playbackQueue)
    }

    func playNext() {
        guard !playbackQueue.isEmpty else { return }
        let index = playbackQueue.firstIndex(where: { $0.audioURL == currentTrack?.audioURL }) ?? -1
        playTrack(playbackQueue[(index + 1) % playbackQueue.count], in: playbackQueue)
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, seconds), player.duration)
        refreshPlaybackTime()
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playbackQueue = []
        subtitleCues = []
        activeCueIndex = nil
        currentTrack = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        setSubtitle("")
        overlayVisible = false
    }

    private func refreshPlaybackTime() {
        guard let player else { return }
        let playbackTime = player.currentTime
        if abs(currentTime - playbackTime) >= 0.08 || isPlaying != player.isPlaying {
            currentTime = playbackTime
        }
        if duration != player.duration { duration = player.duration }
        if isPlaying != player.isPlaying { isPlaying = player.isPlaying }
        let active = subtitleCues.enumerated().filter {
            playbackTime >= $0.element.start && playbackTime < $0.element.end
        }
        let index = active.last?.offset
        if activeCueIndex != index { activeCueIndex = index }
        setSubtitle(active.map { $0.element.text }.joined(separator: "\n"))
    }

    private func setSubtitle(_ text: String) {
        guard subtitleText != text else { return }
        subtitleText = text
        overlay?.updateSubtitleHeight()
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6 || clean.count == 8,
              let value = UInt64(clean, radix: 16) else { return nil }
        let alpha = clean.count == 8 ? CGFloat((value >> 24) & 0xFF) / 255 : 1
        self.init(deviceRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
    }

    var hexString: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        let alpha = Int((color.alphaComponent * 255).rounded())
        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", alpha, red, green, blue)
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
