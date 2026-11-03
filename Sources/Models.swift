import Foundation
import AVFoundation

struct Track: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var artist: String
    var file: String
}

struct Hit: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artwork: URL?
    let audio: URL?
    let downloadable: Bool
}

enum SearchAPI {
    static func itunes(_ q: String) async throws -> [Hit] {
        var c = URLComponents(string: "https://itunes.apple.com/search")!
        c.queryItems = [
            URLQueryItem(name: "term", value: q),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "30")
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        struct Resp: Decodable { let results: [Item] }
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let artworkUrl100: String?
            let previewUrl: String?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return r.results.compactMap { i in
            guard let name = i.trackName, let id = i.trackId else { return nil }
            return Hit(id: "it\(id)", title: name, artist: i.artistName ?? "",
                       artwork: i.artworkUrl100.flatMap { URL(string: $0) },
                       audio: i.previewUrl.flatMap { URL(string: $0) },
                       downloadable: false)
        }
    }

    static func jamendo(_ q: String) async throws -> [Hit] {
        var c = URLComponents(string: "https://api.jamendo.com/v3.0/tracks/")!
        var items = [
            URLQueryItem(name: "client_id", value: Config.jamendoClientID),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "audiodownload_allowed", value: "true")
        ]
        if q.isEmpty {
            items.append(URLQueryItem(name: "order", value: "popularity_week"))
        } else {
            items.append(URLQueryItem(name: "search", value: q))
        }
        c.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        struct Resp: Decodable { let results: [Item] }
        struct Item: Decodable {
            let id: String
            let name: String
            let artist_name: String
            let image: String?
            let audio: String?
        }
        let r = try JSONDecoder().decode(Resp.self, from: data)
        return r.results.map { i in
            Hit(id: "ja" + i.id, title: i.name, artist: i.artist_name,
                artwork: i.image.flatMap { URL(string: $0) },
                audio: i.audio.flatMap { URL(string: $0) },
                downloadable: true)
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var tracks: [Track] = []
    @Published var busy: Set<String> = []
    private let dir: URL
    private let index: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("Songs", isDirectory: true)
        index = docs.appendingPathComponent("library.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: index),
           let t = try? JSONDecoder().decode([Track].self, from: d) {
            tracks = t
        }
    }

    func url(_ t: Track) -> URL { dir.appendingPathComponent(t.file) }

    private func save() {
        if let d = try? JSONEncoder().encode(tracks) { try? d.write(to: index) }
    }

    func has(_ h: Hit) -> Bool {
        tracks.contains { $0.title == h.title && $0.artist == h.artist }
    }

    func add(_ h: Hit) async {
        guard let remote = h.audio, !busy.contains(h.id) else { return }
        busy.insert(h.id)
        defer { busy.remove(h.id) }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: remote)
            let name = UUID().uuidString + ".mp3"
            try FileManager.default.moveItem(at: tmp, to: dir.appendingPathComponent(name))
            tracks.insert(Track(title: h.title, artist: h.artist, file: name), at: 0)
            save()
        } catch {
        }
    }

    func importFiles(_ urls: [URL]) {
        for u in urls {
            let ok = u.startAccessingSecurityScopedResource()
            let ext = u.pathExtension.isEmpty ? "mp3" : u.pathExtension
            let name = UUID().uuidString + "." + ext
            do {
                try FileManager.default.copyItem(at: u, to: dir.appendingPathComponent(name))
                tracks.insert(Track(title: u.deletingPathExtension().lastPathComponent,
                                    artist: "Eigener Song", file: name), at: 0)
            } catch {
            }
            if ok { u.stopAccessingSecurityScopedResource() }
        }
        save()
    }

    func remove(at offsets: IndexSet) {
        for i in offsets { try? FileManager.default.removeItem(at: url(tracks[i])) }
        tracks.remove(atOffsets: offsets)
        save()
    }
}

@MainActor
final class Player: ObservableObject {
    @Published var title = ""
    @Published var playing = false
    private var player: AVPlayer?
    private var observer: NSObjectProtocol?

    func play(_ url: URL, title: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        self.title = title
        player?.play()
        playing = true
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.playing = false }
        }
    }

    func toggle() {
        guard let p = player else { return }
        if playing { p.pause() } else { p.play() }
        playing.toggle()
    }
}
