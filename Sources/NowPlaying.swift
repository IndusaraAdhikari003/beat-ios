import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerModel
    @EnvironmentObject var store: Store
    @EnvironmentObject var clock: PlayClock
    @Environment(\.presentationMode) var presentation
    @State private var dragging = false
    @State private var dragValue: Double = 0
    @State private var sleepDialog = false

    var body: some View {
        let t = player.current
        VStack(spacing: 14) {
            HStack {
                Button { presentation.wrappedValue.dismiss() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 22, weight: .semibold)).padding(8)
                }
                Spacer()
                Text("Now playing").font(.footnote).foregroundColor(.secondary)
                Spacer()
                Color.clear.frame(width: 38, height: 38)
            }

            ArtView(url: t?.art ?? "")
                .aspectRatio(1, contentMode: .fit)
                .cornerRadius(20)
                .padding(.horizontal, 24)
                .frame(maxHeight: .infinity)

            VStack(spacing: 4) {
                Text(t?.title ?? "").font(.system(size: 20, weight: .bold)).lineLimit(2).multilineTextAlignment(.center)
                Text(t?.artist ?? "").font(.system(size: 14)).foregroundColor(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { dragging ? dragValue : min(clock.position, max(clock.duration, 1)) },
                        set: { dragValue = $0 }
                    ),
                    in: 0...max(clock.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            dragValue = clock.position
                            dragging = true
                        } else {
                            player.seek(dragValue)
                            dragging = false
                        }
                    }
                )
                HStack {
                    Text(formatTime(dragging ? dragValue : clock.position))
                    Spacer()
                    Text(formatTime(clock.duration))
                }
                .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 0) {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 20))
                        .foregroundColor(player.shuffle ? .accentColor : .secondary)
                }
                .frame(maxWidth: .infinity)
                Button { player.prev() } label: {
                    Image(systemName: "backward.fill").font(.system(size: 28))
                }
                .frame(maxWidth: .infinity)
                Button { player.toggle() } label: {
                    if player.loading {
                        ProgressView().frame(width: 64, height: 64)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 64))
                    }
                }
                .frame(maxWidth: .infinity)
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.system(size: 28))
                }
                .frame(maxWidth: .infinity)
                Button { player.cycleRepeat() } label: {
                    Image(systemName: player.repeatMode == 2 ? "repeat.1" : "repeat").font(.system(size: 20))
                        .foregroundColor(player.repeatMode == 0 ? .secondary : .accentColor)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                Button {
                    if let t = t { store.toggleFav(t) }
                } label: {
                    let fav = t.map { store.isFav($0.id) } ?? false
                    Image(systemName: fav ? "heart.fill" : "heart").font(.system(size: 22))
                        .foregroundColor(fav ? .accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
                Button {
                    if let t = t {
                        store.pickTrack = t
                    }
                } label: {
                    Image(systemName: "music.note.list").font(.system(size: 22))
                }
                .frame(maxWidth: .infinity)
                Button { sleepDialog = true } label: {
                    Image(systemName: "moon.zzz").font(.system(size: 22))
                        .foregroundColor(player.sleepAt != nil ? .accentColor : .primary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .confirmationDialog("Sleep timer", isPresented: $sleepDialog, titleVisibility: .visible) {
            Button("15 minutes") { player.setSleep(15) }
            Button("30 minutes") { player.setSleep(30) }
            Button("45 minutes") { player.setSleep(45) }
            Button("60 minutes") { player.setSleep(60) }
            Button("Turn off", role: .destructive) { player.setSleep(0) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { player.showFull ? store.pickTrack : nil },
            set: { store.pickTrack = $0 }
        )) { tr in PlaylistPicker(track: tr) }
    }
}
