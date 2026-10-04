import SwiftUI

@main
struct BeatApp: App {
    @StateObject private var store = Store.shared
    @StateObject private var player = PlayerModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(player.clock)
                .accentColor(Color(red: 0.42, green: 0.31, blue: 0.90))
                .preferredColorScheme(store.theme == 1 ? .light : (store.theme == 2 ? .dark : nil))
                .onAppear { store.reloadLibrary() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: PlayerModel

    var body: some View {
        TabView {
            SongsTab()
                .tabItem { Label("Songs", systemImage: "music.note") }
            PlaylistsTab()
                .tabItem { Label("Playlists", systemImage: "music.note.list") }
            YouTubeTab()
                .tabItem { Label("YouTube", systemImage: "play.rectangle") }
        }
        .fullScreenCover(isPresented: $player.showFull) { NowPlayingView() }
        .sheet(item: Binding(
            get: { player.showFull ? nil : store.pickTrack },
            set: { store.pickTrack = $0 }
        )) { t in PlaylistPicker(track: t) }
        .overlay(alignment: .top) {
            if let e = player.error {
                Text(e)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .foregroundColor(.white)
                    .padding(.top, 8)
            }
        }
    }
}
