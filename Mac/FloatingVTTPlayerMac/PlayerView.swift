import AppKit
import SwiftUI

enum PlayerPalette {
    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let background = adaptive(
        dark: NSColor(srgbRed: 0.055, green: 0.067, blue: 0.105, alpha: 1),
        light: NSColor(srgbRed: 0.965, green: 0.973, blue: 0.99, alpha: 1))
    static let surface = adaptive(
        dark: NSColor(srgbRed: 0.09, green: 0.105, blue: 0.16, alpha: 1),
        light: .white)
    static let raised = adaptive(
        dark: NSColor(srgbRed: 0.13, green: 0.15, blue: 0.23, alpha: 1),
        light: NSColor(srgbRed: 0.90, green: 0.92, blue: 0.97, alpha: 1))
    static let line = adaptive(
        dark: NSColor.white.withAlphaComponent(0.09),
        light: NSColor.black.withAlphaComponent(0.11))
    static let accent = adaptive(
        dark: NSColor(srgbRed: 0.61, green: 0.62, blue: 1, alpha: 1),
        light: NSColor(srgbRed: 0.35, green: 0.36, blue: 0.82, alpha: 1))
    static let secondary = adaptive(
        dark: NSColor(srgbRed: 0.67, green: 0.69, blue: 0.78, alpha: 1),
        light: NSColor(srgbRed: 0.39, green: 0.42, blue: 0.51, alpha: 1))
    static let subtitlesGlow = adaptive(
        dark: NSColor(srgbRed: 0.08, green: 0.12, blue: 0.24, alpha: 1),
        light: NSColor(srgbRed: 0.85, green: 0.88, blue: 0.98, alpha: 1))
}

struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @AppStorage("playerDarkMode") private var isDarkMode = true
    @State private var searchText = ""
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    @State private var showRenamePlaylist = false
    @State private var renamePlaylistID: UUID?
    @State private var renamedPlaylistName = ""
    @State private var folderSelectionMode = false
    @State private var selectedFolderIDs: Set<String> = []
    @State private var showRemoveFoldersConfirmation = false
    @State private var showRenameFolder = false
    @State private var renameFolderID: String?
    @State private var renamedFolderName = ""
    @State private var showVolume = false
    @State private var showingSubtitlesPage = false
    @FocusState private var searchFocused: Bool

    private var hasSearch: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var displayedTracks: [AudioTrack] {
        hasSearch ? model.searchFilenames(searchText) : model.visibleTracks
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingSubtitlesPage {
                ScrollingSubtitlesView(model: model) {
                    showingSubtitlesPage = false
                }
            } else {
                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 236)
                    Rectangle().fill(PlayerPalette.line).frame(width: 1)
                    VStack(spacing: 0) {
                        searchHeader
                        Rectangle().fill(PlayerPalette.line).frame(height: 1)
                        ScrollView {
                            Group {
                                if hasSearch {
                                    searchPage
                                } else {
                                    switch model.selection {
                                    case .allFiles: allFilesPage
                                    case .recentlyAdded:
                                        trackCollectionPage(title: "Recently Added",
                                                            detail: "New audio from your imported folders",
                                                            tracks: displayedTracks)
                                    case .favorites:
                                        trackCollectionPage(title: "Favorites",
                                                            detail: "Tracks you marked as favorites",
                                                            tracks: displayedTracks)
                                    case .playlist(let id):
                                        trackCollectionPage(
                                            title: model.playlists.first(where: { $0.id == id })?.name ?? "Playlist",
                                            detail: "Your personal playlist",
                                            tracks: displayedTracks)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                        }
                        .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
                    }
                }
            }
            Rectangle().fill(PlayerPalette.line).frame(height: 1)
            transport
                .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
        }
        .background(PlayerPalette.background)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            PlayerWindowConfiguration {
                if model.currentTrack != nil { model.togglePlayback() }
            }
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .frame(minWidth: 960, minHeight: 640)
        .onAppear { model.startOverlay() }
        .onChange(of: model.currentTrack?.audioURL) { _, _ in searchFocused = false }
        .alert("Floating VTT Player", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("New Playlist", isPresented: $showCreatePlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Create") {
                model.createPlaylist(named: newPlaylistName)
                newPlaylistName = ""
            }
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
        } message: {
            Text("Give this playlist a name. Right-click a track to add it.")
        }
        .alert("Rename Playlist", isPresented: $showRenamePlaylist) {
            TextField("Playlist name", text: $renamedPlaylistName)
            Button("Save") {
                if let renamePlaylistID {
                    model.renamePlaylist(renamePlaylistID, to: renamedPlaylistName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Folder", isPresented: $showRenameFolder) {
            TextField("Folder name", text: $renamedFolderName)
            Button("Save") {
                if let renameFolderID { model.renameFolder(renameFolderID, to: renamedFolderName) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Change the name shown in your library. Files on disk stay in place.")
        }
        .alert("Remove \(selectedFolderIDs.count) \(selectedFolderIDs.count == 1 ? "folder" : "folders")?",
               isPresented: $showRemoveFoldersConfirmation) {
            Button("Remove", role: .destructive) {
                model.removeFolders(selectedFolderIDs)
                resetFolderSelection()
                model.selectAllFiles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove the selected \(selectedFolderIDs.count == 1 ? "folder" : "folders") from your library? Files on disk will stay in place.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)
            HStack(spacing: 11) {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(PlayerPalette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Floating VTT Player")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text("Local audio · synced subtitles")
                        .font(.system(size: 10))
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 29)

            Text("Your Library")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PlayerPalette.secondary)
                .padding(.bottom, 9)
            sidebarItem("All Files", icon: "folder.fill",
                        count: model.folders.count,
                        selected: model.selection == .allFiles && !hasSearch) {
                searchText = ""
                resetFolderSelection()
                model.selectAllFiles()
            }
            sidebarItem("Recently Added", icon: "clock",
                        count: model.allTracks.count,
                        selected: model.selection == .recentlyAdded && !hasSearch) {
                searchText = ""
                resetFolderSelection()
                model.selectRecentlyAdded()
            }
            sidebarItem("Favorites", icon: "heart",
                        count: model.allTracks.filter(model.isFavorite).count,
                        selected: model.selection == .favorites && !hasSearch) {
                searchText = ""
                resetFolderSelection()
                model.selectFavorites()
            }

            Rectangle().fill(PlayerPalette.line)
                .frame(height: 1)
                .padding(.vertical, 18)

            HStack {
                Text("Playlists")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PlayerPalette.secondary)
                Spacer()
                Button {
                    newPlaylistName = ""
                    showCreatePlaylist = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 25, height: 25)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Create playlist")
                .accessibilityLabel("Create playlist")
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 7)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(model.playlists) { playlist in
                        sidebarItem(playlist.name, icon: "music.note.list",
                                    count: playlist.trackPaths.count,
                                    selected: model.selection == .playlist(playlist.id) && !hasSearch) {
                            searchText = ""
                            resetFolderSelection()
                            model.selectPlaylist(playlist.id)
                        }
                        .contextMenu {
                            Button("Rename") {
                                renamePlaylistID = playlist.id
                                renamedPlaylistName = playlist.name
                                showRenamePlaylist = true
                            }
                            Button("Delete Playlist", role: .destructive) {
                                model.deletePlaylist(playlist.id)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(PlayerPalette.surface.opacity(0.55))
        .simultaneousGesture(TapGesture().onEnded { searchFocused = false })
    }

    private func sidebarItem(_ title: String, icon: String, count: Int, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 19)
                    .foregroundStyle(selected ? PlayerPalette.accent : PlayerPalette.secondary)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(PlayerPalette.secondary)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .regular))
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(selected ? PlayerPalette.accent.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { isDarkMode.toggle() } label: {
                Image(systemName: isDarkMode ? "sun.max" : "moon")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(PlayerPalette.accent)
                    .frame(width: 34, height: 34)
                    .background(PlayerPalette.surface, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(PlayerPalette.line))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isDarkMode ? "Switch to light mode" : "Switch to dark mode")
            .accessibilityLabel(isDarkMode ? "Switch to light mode" : "Switch to dark mode")
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(PlayerPalette.secondary)
                TextField("Search filenames…", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("Search filenames")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(PlayerPalette.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .frame(width: 221, height: 34)
            .background(PlayerPalette.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(PlayerPalette.line))
        }
        .padding(.horizontal, 24)
        .frame(height: 60)
    }

    private var allFilesPage: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                pageHeading("All Files",
                            detail: model.folders.count == 1 ? "1 folder" : "\(model.folders.count) folders")
                Spacer()
                if folderSelectionMode {
                    Button {
                        resetFolderSelection()
                        model.selectAllFiles()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 22)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .help("Cancel folder selection")
                    .accessibilityLabel("Cancel folder selection")
                    Button("Remove") {
                        showRemoveFoldersConfirmation = true
                    }
                    .buttonStyle(AccentButtonStyle())
                    .disabled(selectedFolderIDs.isEmpty)
                } else {
                    if !model.folders.isEmpty {
                        Button {
                            folderSelectionMode = true
                            selectedFolderIDs.removeAll()
                            model.selectAllFiles()
                        } label: {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 22)
                        }
                        .buttonStyle(AccentButtonStyle())
                        .help("Select folders")
                        .accessibilityLabel("Select Folders")
                    }
                    Button { model.chooseFolders() } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 22)
                    }
                    .buttonStyle(AccentButtonStyle())
                    .help("Add folder")
                    .accessibilityLabel("Add Folder")
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                Text("Folders").font(.system(size: 16, weight: .semibold))
                if model.folders.isEmpty {
                    emptyState(icon: "folder.badge.plus",
                               message: "Add a folder to start your library.")
                        .frame(height: 125)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 12) {
                        ForEach(model.folders) { folder in folderCard(folder) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("Tracks").font(.system(size: 16, weight: .semibold))
                    if let folder = model.selectedFolder {
                        Text("· \(folder.name)")
                            .font(.system(size: 12))
                            .foregroundStyle(PlayerPalette.secondary)
                    }
                }
                if let folder = model.selectedFolder {
                    if folder.tracks.isEmpty {
                        emptyState(icon: "music.note.list",
                                   message: folder.isAvailable
                                   ? "No MP3 or WAV files in this folder."
                                   : "This folder is unavailable. Select it again to retry.")
                            .frame(height: 220)
                    } else {
                        trackList(folder.tracks, showFolder: false)
                    }
                } else {
                    emptyState(icon: "folder",
                               message: "Select a folder to view its tracks")
                        .frame(minHeight: 250)
                }
            }
        }
    }

    private func folderCard(_ folder: LibraryFolder) -> some View {
        let selected = folderSelectionMode
            ? selectedFolderIDs.contains(folder.id)
            : model.selectedFolderID == folder.id
        return HStack(spacing: 0) {
            Button { selectFolderCard(folder) } label: {
            HStack(spacing: 12) {
                Image(systemName: folderSelectionMode
                      ? (selected ? "checkmark.circle.fill" : "circle")
                      : "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(!folderSelectionMode || selected
                                     ? PlayerPalette.accent : PlayerPalette.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(folder.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(folder.isAvailable
                         ? "\(folder.tracks.count) \(folder.tracks.count == 1 ? "track" : "tracks") · \(folder.subtitleCount) VTT"
                         : "Unavailable")
                        .font(.system(size: 10))
                        .foregroundStyle(PlayerPalette.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(folderSelectionMode
                                ? "\(selected ? "Deselect" : "Select") \(folder.name)"
                                : "Open \(folder.name)")
            if !folderSelectionMode {
                Button { beginRenameFolder(folder) } label: {
                    Image(systemName: "pencil")
                        .foregroundStyle(PlayerPalette.secondary)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rename folder in library")
                .accessibilityLabel("Rename \(folder.name)")
                .padding(.trailing, 8)
            }
        }
        .background(selected ? PlayerPalette.accent.opacity(0.16) : PlayerPalette.surface,
                    in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11)
            .stroke(selected ? PlayerPalette.accent.opacity(0.55) : PlayerPalette.line))
        .help(folder.url.path)
        .contextMenu {
            Button("Rename in Library") { beginRenameFolder(folder) }
            Button("Remove from Library", role: .destructive) {
                model.removeFolder(folder.id)
                selectedFolderIDs.remove(folder.id)
            }
        }
    }

    private func selectFolderCard(_ folder: LibraryFolder) {
        guard folderSelectionMode else {
            model.selectFolder(folder.id)
            return
        }
        if !selectedFolderIDs.insert(folder.id).inserted {
            selectedFolderIDs.remove(folder.id)
        }
        if selectedFolderIDs.count == 1, let onlyID = selectedFolderIDs.first {
            model.selectFolder(onlyID)
        } else {
            model.selectAllFiles()
        }
    }

    private func beginRenameFolder(_ folder: LibraryFolder) {
        renameFolderID = folder.id
        renamedFolderName = folder.name
        showRenameFolder = true
    }

    private func resetFolderSelection() {
        folderSelectionMode = false
        selectedFolderIDs.removeAll()
    }

    private var searchPage: some View {
        trackCollectionPage(
            title: "Search Results",
            detail: "\(displayedTracks.count) filename matches for “\(searchText)”",
            tracks: displayedTracks,
            emptyMessage: "No matching filenames")
    }

    private func trackCollectionPage(title: String, detail: String, tracks: [AudioTrack],
                                     emptyMessage: String = "No tracks yet") -> some View {
        VStack(alignment: .leading, spacing: 25) {
            pageHeading(title, detail: detail)
            if tracks.isEmpty {
                emptyState(icon: "music.note.list", message: emptyMessage)
                    .frame(minHeight: 300)
            } else {
                trackList(tracks, showFolder: true)
            }
        }
    }

    private func pageHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 25, weight: .bold))
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(PlayerPalette.secondary)
        }
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(PlayerPalette.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(PlayerPalette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlayerPalette.surface.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 12))
    }

    private func trackList(_ tracks: [AudioTrack], showFolder: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("FILENAME")
                Spacer(minLength: 0)
                if showFolder { Text("FOLDER").frame(width: 125, alignment: .leading) }
                Text("VTT").frame(width: 85, alignment: .leading)
                Text("FAVORITE").frame(width: 65, alignment: .center)
            }
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(PlayerPalette.secondary)
            .padding(.horizontal, 15)
            .frame(height: 31)

            LazyVStack(spacing: 1) {
                ForEach(tracks) { track in
                    trackRow(track, queue: tracks, showFolder: showFolder)
                }
            }
        }
        .background(PlayerPalette.surface.opacity(0.42),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(PlayerPalette.line))
    }

    private func trackRow(_ track: AudioTrack, queue: [AudioTrack], showFolder: Bool) -> some View {
        let selected = model.currentTrack?.audioURL == track.audioURL
        return HStack(spacing: 0) {
            Button {
                model.playTrack(track, in: queue)
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: selected && model.isPlaying ? "waveform" : "play.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? PlayerPalette.accent : PlayerPalette.secondary)
                        .frame(width: 25, alignment: .leading)
                    Text(track.fileName)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if showFolder {
                        Text(model.folderContaining(track)?.name ?? "")
                            .font(.system(size: 10))
                            .foregroundStyle(PlayerPalette.secondary)
                            .lineLimit(1)
                            .frame(width: 125, alignment: .leading)
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(track.hasSubtitle ? Color.mint : PlayerPalette.secondary)
                            .frame(width: 6, height: 6)
                        Text(track.hasSubtitle ? "Synced" : "None")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(track.hasSubtitle ? Color.mint : PlayerPalette.secondary)
                    .frame(width: 85, alignment: .leading)
                    .offset(x: -3)
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Play \(track.fileName)")

            Button { model.toggleFavorite(track) } label: {
                Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                    .foregroundStyle(model.isFavorite(track)
                                     ? Color(red: 0.96, green: 0.30, blue: 0.39)
                                     : PlayerPalette.secondary)
                    .frame(width: 65, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites")
        }
        .padding(.horizontal, 15)
        .frame(height: 42)
        .background(selected ? PlayerPalette.accent.opacity(0.16) : .clear)
        .contextMenu {
                if !model.playlists.isEmpty {
                    Menu("Add to Playlist") {
                        ForEach(model.playlists) { playlist in
                            Button(playlist.name) { model.addTrack(track, toPlaylist: playlist.id) }
                        }
                    }
                }
                if case .playlist(let id) = model.selection, !hasSearch {
                    Button("Remove from Playlist") { model.removeTrack(track, fromPlaylist: id) }
                }
                Button(model.isFavorite(track) ? "Remove from Favorites" : "Add to Favorites") {
                    model.toggleFavorite(track)
                }
        }
    }

    private var transport: some View {
        GeometryReader { geometry in
            ZStack {
                HStack {
                    trackSummary.frame(width: 220, alignment: .leading)
                    Spacer(minLength: 0)
                    transportActions.frame(width: 136, alignment: .trailing)
                }
                .padding(.horizontal, 22)
                playbackControls
                    .frame(width: min(560, max(360, geometry.size.width - 480)))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 105)
        .background(PlayerPalette.surface)
    }

    private var trackSummary: some View {
        HStack(spacing: 11) {
            Image(systemName: "music.note")
                .font(.system(size: 19))
                .foregroundStyle(PlayerPalette.secondary)
                .frame(width: 42, height: 42)
                .background(PlayerPalette.raised, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentTrack?.fileName ?? "Nothing playing")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.currentTrack != nil {
                    Text("\(Self.formatTime(model.currentTime)) / \(Self.formatTime(model.duration))")
                        .font(.system(size: 10))
                        .foregroundStyle(PlayerPalette.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var playbackControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 22) {
                Button { model.playPrevious() } label: {
                    Image(systemName: "backward.end.fill")
                }
                .help("Previous track")
                .disabled(model.currentTrack == nil)
                Button {
                    if model.currentTrack == nil {
                        if let first = displayedTracks.first {
                            model.playTrack(first, in: displayedTracks)
                        }
                    } else {
                        model.togglePlayback()
                    }
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(PlayerPalette.background)
                        .background(PlayerPalette.accent, in: Circle())
                }
                .help(model.isPlaying ? "Pause" : "Play")
                .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
                .disabled(model.currentTrack == nil && displayedTracks.isEmpty)
                Button { model.playNext() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .help("Next track")
                .disabled(model.currentTrack == nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            HStack(spacing: 8) {
                Text(Self.formatTime(model.currentTime))
                Slider(value: Binding(get: { model.currentTime },
                                      set: { model.seek(to: $0) }),
                       in: 0...max(1, model.duration))
                    .disabled(model.currentTrack == nil)
                    .tint(PlayerPalette.accent)
                    .accessibilityLabel("Playback position")
                Text(Self.formatTime(model.duration))
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(PlayerPalette.secondary)
        }
    }

    private var transportActions: some View {
        HStack(spacing: 8) {
            Button { model.overlayVisible.toggle() } label: {
                Image(systemName: model.overlayVisible ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 17))
                    .foregroundStyle(model.overlayVisible ? PlayerPalette.accent : PlayerPalette.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.overlayVisible ? "Hide floating subtitles" : "Show floating subtitles")
            .accessibilityLabel(model.overlayVisible ? "Hide floating subtitles" : "Show floating subtitles")
            Button { showVolume.toggle() } label: {
                Image(systemName: model.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 17))
                    .foregroundStyle(PlayerPalette.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Adjust volume")
            .accessibilityLabel("Volume")
            .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                VerticalVolumeControl(value: $model.volume)
            }
            Button { showingSubtitlesPage.toggle() } label: {
                Image(systemName: showingSubtitlesPage
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(PlayerPalette.secondary)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(showingSubtitlesPage ? "Return to library" : "Show scrolling subtitles")
            .accessibilityLabel(showingSubtitlesPage ? "Return to library" : "Show scrolling subtitles")
        }
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let seconds = max(0, Int(time))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct VerticalVolumeControl: View {
    @Binding var value: Double

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(PlayerPalette.secondary)
            GeometryReader { geometry in
                let travel: CGFloat = max(1, geometry.size.height - 16)
                let fillHeight: CGFloat = travel * CGFloat(value)
                let knobY: CGFloat = 8 + travel * (1 - CGFloat(value))
                ZStack {
                    Capsule()
                        .fill(PlayerPalette.secondary.opacity(0.35))
                        .frame(width: 5, height: travel)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    Capsule()
                        .fill(PlayerPalette.accent)
                        .frame(width: 5, height: fillHeight)
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height - 8 - fillHeight / 2)
                    Circle()
                        .fill(.white)
                        .frame(width: 15, height: 15)
                        .shadow(color: .black.opacity(0.3), radius: 3)
                        .position(x: geometry.size.width / 2, y: knobY)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    value = Double(min(1, max(0, 1 - (drag.location.y - 8) / travel)))
                })
            }
            .frame(width: 38, height: 130)
        }
        .padding(13)
        .background(PlayerPalette.surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.05)
            case .decrement: value = max(0, value - 0.05)
            @unknown default: break
            }
        }
    }
}

private struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(PlayerPalette.accent.opacity(isEnabled
                                                     ? (configuration.isPressed ? 0.75 : 1)
                                                     : 0.3),
                        in: RoundedRectangle(cornerRadius: 9))
    }
}

struct PlayerMenu: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Player") {
            openWindow(id: "player")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button(model.isPlaying ? "Pause" : "Play") { model.togglePlayback() }
            .disabled(model.currentTrack == nil && model.visibleTracks.isEmpty)
        Button("Previous") { model.playPrevious() }.disabled(model.currentTrack == nil)
        Button("Next") { model.playNext() }.disabled(model.currentTrack == nil)
        Divider()
        Button("Quit Floating VTT Player") { NSApp.terminate(nil) }
    }
}
