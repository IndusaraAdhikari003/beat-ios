import SwiftUI
import UniformTypeIdentifiers

struct ArtView: View {
    let url: String
    var body: some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.18))
            Image(systemName: "music.note").foregroundColor(.secondary)
            if !url.isEmpty, let u = URL(string: url) {
                AsyncImage(url: u) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Color.clear
                    }
                }
            }
        }
        .clipped()
    }
}

struct TrackMenu: View {
    let t: Track
    var extra: [MenuAction] = []
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        Button { player.playNext(t) } label: { Label("Play next", systemImage: "arrow.turn.down.right") }
        Button { player.enqueue(t) } label: { Label("Add to queue", systemImage: "text.badge.plus") }
        Button { store.pickTrack = t } label: { Label("Add to playlist", systemImage: "music.note.list") }
        Button { store.toggleFav(t) } label: {
            Label(store.isFav(t.id) ? "Remove from favourites" : "Add to favourites",
                  systemImage: store.isFav(t.id) ? "heart.slash" : "heart")
        }
        ForEach(extra) { a in
            Button { a.action() } label: { Label(a.title, systemImage: a.icon) }
        }
    }
}

struct SongRow: View {
    let t: Track
    var extra: [MenuAction] = []
    let onTap: () -> Void
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        let isCurrent = player.current?.id == t.id
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                ArtView(url: t.art).frame(width: 46, height: 46).cornerRadius(8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title).lineLimit(1)
                        .font(.system(size: 15, weight: isCurrent ? .bold : .regular))
                        .foregroundColor(isCurrent ? .accentColor : .primary)
                    Text(t.artist).lineLimit(1)
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            Menu {
                TrackMenu(t: t, extra: extra)
            } label: {
                Image(systemName: "ellipsis").padding(10).foregroundColor(.secondary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .contextMenu { TrackMenu(t: t, extra: extra) }
    }
}

struct PlayShuffleButtons: View {
    let list: [Track]
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        HStack(spacing: 10) {
            Button { player.play(list, at: 0) } label: {
                Label("Play all", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedProminentButtonStyle())
            Button { player.play(list.shuffled(), at: 0) } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(BorderedButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        Group {
            if let t = player.current {
                HStack(spacing: 12) {
                    ArtView(url: t.art).frame(width: 40, height: 40).cornerRadius(6)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(t.artist).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if player.loading {
                        ProgressView().padding(.horizontal, 8)
                    } else {
                        Button { player.toggle() } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20)).frame(width: 40, height: 40)
                        }
                    }
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(.system(size: 18)).frame(width: 40, height: 40)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
                .contentShape(Rectangle())
                .onTapGesture { player.showFull = true }
            }
        }
    }
}

struct NameSheet: View {
    let title: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.presentationMode) var presentation

    var body: some View {
        NavigationView {
            Form {
                TextField("Name", text: $text)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentation.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if !text.trimmed.isEmpty { onSave(text) }
                        presentation.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct PlaylistPicker: View {
    let track: Track
    @EnvironmentObject var store: Store
    @Environment(\.presentationMode) var presentation
    @State private var creating = false

    var body: some View {
        NavigationView {
            List {
                ForEach(store.playlists) { p in
                    Button {
                        store.add(track, to: p.id)
                        presentation.wrappedValue.dismiss()
                    } label: {
                        HStack {
                            Image(systemName: p.id == Store.favID ? "heart.fill" : "music.note.list")
                            Text(p.name)
                            Spacer()
                            Text("\(p.tracks.count)").foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                Button { creating = true } label: { Label("New playlist", systemImage: "plus") }
            }
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { presentation.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $creating) {
                NameSheet(title: "New playlist", text: "") { name in
                    let id = store.createPlaylist(name)
                    store.add(track, to: id)
                    presentation.wrappedValue.dismiss()
                }
            }
        }
    }
}

struct DocPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let p = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio], asCopy: true)
        p.allowsMultipleSelection = true
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(_ f: @escaping ([URL]) -> Void) { onPick = f }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.presentationMode) var presentation

    var hiddenTracks: [Track] { store.library.filter { store.hidden.contains($0.id) } }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Theme")) {
                    Picker("Theme", selection: $store.theme) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("YouTube")) {
                    Toggle("Autoplay similar songs", isOn: $store.autoplay)
                }
                Section(header: Text("Hidden songs (\(hiddenTracks.count))")) {
                    if hiddenTracks.isEmpty {
                        Text("Songs you hide show up here.").foregroundColor(.secondary)
                    } else {
                        ForEach(hiddenTracks) { t in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.title).lineLimit(1)
                                    Text(t.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Button("Unhide") { store.unhide(t.id) }
                            }
                        }
                        Button("Unhide all") { store.unhideAll() }
                    }
                }
                Section(footer: Text("YouTube playback is for personal use. If YouTube songs stop working one day, the app needs an update.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { presentation.wrappedValue.dismiss() }
                }
            }
        }
    }
}

struct SettingsButton: ViewModifier {
    @State private var show = false
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { show = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $show) { SettingsView() }
    }
}

extension View {
    func settingsButton() -> some View { modifier(SettingsButton()) }
}
