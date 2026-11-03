import SwiftUI
import UniformTypeIdentifiers

struct MiniPlayer: View {
    @EnvironmentObject var player: Player
    var body: some View {
        if !player.title.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "waveform").foregroundColor(.vp)
                Text(player.title).lineLimit(1)
                Spacer()
                Button { player.toggle() } label: {
                    Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.title3)
                }
            }
            .padding(14)
            .background(Color.panel)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.vp.opacity(0.4)), alignment: .top)
        }
    }
}

struct HitRow: View {
    let hit: Hit
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: Player

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: hit.artwork) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.vp.opacity(0.3)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).bold().lineLimit(1)
                Text(hit.artist).font(.footnote).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            if let a = hit.audio {
                Button { player.play(a, title: hit.title) } label: {
                    Image(systemName: "play.circle").font(.title2)
                }
                .buttonStyle(.borderless)
            }
            if hit.downloadable {
                if store.has(hit) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.title2)
                } else if store.busy.contains(hit.id) {
                    ProgressView()
                } else {
                    Button { Task { await store.add(hit) } } label: {
                        Image(systemName: "arrow.down.circle.fill").font(.title2)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listRowBackground(Color.panel)
    }
}

struct SearchView: View {
    @State private var query = ""
    @State private var mode = 0
    @State private var hits: [Hit] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Quelle", selection: $mode) {
                    Text("Alle Songs (Vorschau)").tag(0)
                    Text("Frei (ganz laden)").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                List {
                    if loading { ProgressView() }
                    if let e = error { Text(e).foregroundColor(.secondary) }
                    ForEach(hits) { h in HitRow(hit: h) }
                    if mode == 0 {
                        Text("Vorschau: 30 Sekunden. Ganze Songs gibt es bei Apple Music oder Spotify. Zum Laden und Offline-Hören wähle „Frei“.")
                            .font(.footnote).foregroundColor(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color.black)
            .navigationTitle("Vynox")
            .searchable(text: $query, prompt: "Song oder Künstler")
            .onSubmit(of: .search) { Task { await run() } }
            .onChange(of: mode) { _ in
                hits = []
                Task { await run() }
            }
            .task { await run() }
            .safeAreaInset(edge: .bottom) { MiniPlayer() }
        }
    }

    func run() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        error = nil
        if mode == 0 && q.isEmpty { hits = []; return }
        if mode == 1 && Config.jamendoClientID.hasPrefix("DEINE") {
            error = "Trage in Config.swift deine Jamendo-ID ein."
            return
        }
        loading = true
        do {
            hits = mode == 0 ? try await SearchAPI.itunes(q) : try await SearchAPI.jamendo(q)
        } catch {
            hits = []
            self.error = "Suche fehlgeschlagen. Prüfe dein Internet."
        }
        loading = false
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var player: Player
    @State private var importing = false

    var body: some View {
        NavigationStack {
            Group {
                if store.tracks.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list").font(.system(size: 44)).foregroundColor(.vp)
                        Text("Noch keine Songs").font(.headline)
                        Text("Lade Songs über „Suchen“ oder tippe auf +, um eigene Songs zu importieren.")
                            .font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        ForEach(store.tracks) { t in
                            Button { player.play(store.url(t), title: t.title) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "music.note")
                                        .frame(width: 44, height: 44)
                                        .background(Color.vp.opacity(0.3))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(t.title).bold().lineLimit(1)
                                        Text(t.artist + " · offline").font(.footnote).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .foregroundColor(.primary)
                            .listRowBackground(Color.panel)
                        }
                        .onDelete(perform: store.remove)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .navigationTitle("Bibliothek")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { store.importFiles(urls) }
            }
            .safeAreaInset(edge: .bottom) { MiniPlayer() }
        }
    }
}
