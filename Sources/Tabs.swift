import SwiftUI

// MARK: - Songs

struct SongsTab: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: PlayerModel
    @State private var query = ""
    @State private var sortByArtist = false
    @State private var importing = false

    var shown: [Track] {
        var l = store.library.filter { !store.hidden.contains($0.id) }
        if !query.isEmpty {
            l = l.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query)
            }
        }
        if sortByArtist { l.sort { $0.artist.lowercased() < $1.artist.lowercased() } }
        return l
    }

    var body: some View {
        NavigationView {
            Group {
                if store.library.isEmpty {
                    VStack(spacing: 14) {
                        if store.loadingLibrary {
                            ProgressView()
                        } else {
                            Image(systemName: "music.note.list").font(.system(size: 44)).foregroundColor(.secondary)
                            Text("No songs yet").font(.headline)
                            Text("Tap Import and pick your music files.\nOr open the Files app, go to On My iPhone → Beat, and copy your mp3 files there.")
                                .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                            Button("Import songs") { importing = true }.buttonStyle(BorderedProminentButtonStyle())
                        }
                    }
                    .padding(24)
                } else {
                    List {
                        PlayShuffleButtons(list: shown).listRowSeparator(.hidden)
                        ForEach(shown) { t in
                            SongRow(
                                t: t,
                                extra: [MenuAction(title: "Hide song", icon: "eye.slash") { store.hide(t.id) }]
                            ) {
                                if let i = shown.firstIndex(of: t) { player.play(shown, at: i) }
                            }
                            .swipeActions(edge: .trailing) {
                                Button { store.hide(t.id) } label: { Label("Hide", systemImage: "eye.slash") }
                                    .tint(.gray)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .searchable(text: $query, prompt: "Search songs")
                    .refreshable { store.reloadLibrary() }
                }
            }
            .navigationTitle("Songs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { importing = true } label: { Label("Import songs", systemImage: "square.and.arrow.down") }
                        Button { store.reloadLibrary() } label: { Label("Rescan", systemImage: "arrow.clockwise") }
                        Button { sortByArtist.toggle() } label: {
                            Label(sortByArtist ? "Sort by title" : "Sort by artist", systemImage: "arrow.up.arrow.down")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .settingsButton()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .safeAreaInset(edge: .bottom) { MiniPlayer() }
        .sheet(isPresented: $importing) { DocPicker { urls in store.importFiles(urls) } }
    }
}

// MARK: - Playlists

struct PlaylistsTab: View {
    @EnvironmentObject var store: Store
    @State private var creating = false

    var body: some View {
        NavigationView {
            List {
                ForEach(store.playlists) { p in
                    NavigationLink(destination: PlaylistView(id: p.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: p.id == Store.favID ? "heart.fill" : "music.note.list")
                                .frame(width: 32).foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text(p.name)
                                Text("\(p.tracks.count) songs").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.playlists[$0].id }
                    for pid in ids { store.deletePlaylist(pid) }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .settingsButton()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .safeAreaInset(edge: .bottom) { MiniPlayer() }
        .sheet(isPresented: $creating) {
            NameSheet(title: "New playlist", text: "") { store.createPlaylist($0) }
        }
    }
}

struct PlaylistView: View {
    let id: String
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: PlayerModel
    @State private var renaming = false
    @State private var confirmDelete = false
    @Environment(\.presentationMode) var presentation

    var playlist: Playlist? { store.playlists.first(where: { $0.id == id }) }

    var body: some View {
        Group {
            if let p = playlist {
                if p.tracks.isEmpty {
                    VStack(spacing: 10) {
                        Text("No songs yet").font(.headline)
                        Text("Tap ⋯ on any song and choose \"Add to playlist\".")
                            .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    List {
                        PlayShuffleButtons(list: p.tracks).listRowSeparator(.hidden)
                        ForEach(p.tracks) { t in
                            SongRow(
                                t: t,
                                extra: [MenuAction(title: "Remove from playlist", icon: "trash") {
                                    store.removeTrack(t.id, from: id)
                                }]
                            ) {
                                if let i = p.tracks.firstIndex(of: t) { player.play(p.tracks, at: i) }
                            }
                        }
                        .onDelete { store.removeTracks(at: $0, from: id) }
                        .onMove { store.moveTracks(in: id, from: $0, to: $1) }
                    }
                    .listStyle(PlainListStyle())
                }
            } else {
                Text("Playlist not found").foregroundColor(.secondary)
            }
        }
        .navigationTitle(playlist?.name ?? "Playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if let p = playlist, p.tracks.count > 1 { EditButton() }
                    if id != Store.favID {
                        Menu {
                            Button { renaming = true } label: { Label("Rename", systemImage: "pencil") }
                            Button { confirmDelete = true } label: { Label("Delete playlist", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                }
            }
        }
        .sheet(isPresented: $renaming) {
            NameSheet(title: "Rename playlist", text: playlist?.name ?? "") { store.rename(id, $0) }
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.deletePlaylist(id)
                presentation.wrappedValue.dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - YouTube

final class YTModel: ObservableObject {
    static let shared = YTModel()
    @Published var query = ""
    @Published var results: [Track] = []
    @Published var searching = false
    @Published var loading = false
    @Published var error: String?
    @Published var home: [YShelf] = []
    @Published var homeLoading = false
    @Published var homeError: String?

    func search() {
        let text = query.trimmed
        guard !text.isEmpty, !loading else { return }
        searching = true
        loading = true
        error = nil
        results = []
        Task {
            var found: [Track] = []
            var err: String? = nil
            do {
                if let pl = YT.playlistId(text) {
                    found = try await YM.browseTracks("VL" + pl)
                } else if let v = YT.videoId(text) {
                    if let t = try await YM.songInfo(v) { found = [t] }
                } else {
                    found = try await YM.search(text)
                }
                if found.isEmpty { err = "No results" }
            } catch {
                err = "Search failed. Check your internet and try again."
            }
            await MainActor.run {
                self.results = found
                self.error = err
                self.loading = false
            }
        }
    }

    func loadHome() async {
        let busy = await MainActor.run { () -> Bool in
            if self.homeLoading { return true }
            self.homeLoading = true
            self.homeError = nil
            return false
        }
        if busy { return }
        var shelves: [YShelf] = []
        var err: String? = nil
        do {
            shelves = try await YM.home()
            if shelves.isEmpty { err = "Couldn't load recommendations." }
        } catch {
            err = "Couldn't load YouTube. Check your internet."
        }
        await MainActor.run {
            self.home = shelves
            self.homeError = err
            self.homeLoading = false
        }
    }
}

struct YouTubeTab: View {
    @EnvironmentObject var player: PlayerModel
    @ObservedObject private var yt = YTModel.shared

    var body: some View {
        NavigationView {
            Group {
                if yt.searching {
                    if yt.loading {
                        ProgressView()
                    } else if yt.results.isEmpty {
                        Text(yt.error ?? "No results").foregroundColor(.secondary).padding()
                    } else {
                        List {
                            PlayShuffleButtons(list: yt.results).listRowSeparator(.hidden)
                            ForEach(yt.results) { t in
                                // tap = play this song, similar songs follow automatically
                                SongRow(t: t) { player.play([t], at: 0) }
                            }
                        }
                        .listStyle(PlainListStyle())
                    }
                } else {
                    YouTubeHome()
                }
            }
            .navigationTitle("YouTube")
            .searchable(text: $yt.query, prompt: "Search a song or paste a link")
            .onSubmit(of: .search) { yt.search() }
            .onChange(of: yt.query) { q in
                if q.isEmpty { yt.searching = false }
            }
            .settingsButton()
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .safeAreaInset(edge: .bottom) { MiniPlayer() }
    }
}

struct YouTubeHome: View {
    @EnvironmentObject var player: PlayerModel
    @ObservedObject private var yt = YTModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if yt.homeLoading && yt.home.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if yt.home.isEmpty {
                    VStack(spacing: 10) {
                        Text(yt.homeError ?? "Search for a song, or load recommendations.")
                            .foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("Try again") { Task { await yt.loadHome() } }
                            .buttonStyle(BorderedProminentButtonStyle())
                    }
                    .frame(maxWidth: .infinity).padding(24)
                }
                ForEach(yt.home) { shelf in
                    Text(shelf.title).font(.title3.bold()).padding(.horizontal).padding(.top, 14)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 10) {
                            ForEach(shelf.cards) { c in YCardView(card: c) }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable { await yt.loadHome() }
        .task { if yt.home.isEmpty { await yt.loadHome() } }
    }
}

struct YCardView: View {
    let card: YCard
    @EnvironmentObject var player: PlayerModel

    var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            ArtView(url: card.thumb).frame(width: 130, height: 130).cornerRadius(10)
            Text(card.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(card.sub).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(width: 130, alignment: .leading)
    }

    var body: some View {
        if let t = card.track {
            Button { player.play([t], at: 0) } label: { content }.buttonStyle(PlainButtonStyle())
        } else if !card.browseId.isEmpty {
            NavigationLink(destination: YTDetailView(title: card.title, browseId: card.browseId)) { content }
                .buttonStyle(PlainButtonStyle())
        } else {
            Button {
                Task {
                    if let l = try? await YM.radio(videoId: nil, playlistId: card.playlistId), !l.isEmpty {
                        await MainActor.run { player.play(l, at: 0) }
                    }
                }
            } label: { content }.buttonStyle(PlainButtonStyle())
        }
    }
}

struct YTDetailView: View {
    let title: String
    let browseId: String
    @EnvironmentObject var player: PlayerModel
    @State private var tracks: [Track] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Group {
            if loading {
                ProgressView()
            } else if tracks.isEmpty {
                Text(failed ? "Couldn't open this. Try again." : "No songs found here.")
                    .foregroundColor(.secondary).padding()
            } else {
                List {
                    PlayShuffleButtons(list: tracks).listRowSeparator(.hidden)
                    ForEach(tracks) { t in
                        SongRow(t: t) {
                            if let i = tracks.firstIndex(of: t) { player.play(tracks, at: i) }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                tracks = try await YM.browseTracks(browseId)
            } catch {
                failed = true
            }
            loading = false
        }
    }
}
