import SwiftUI

extension Color {
    static let vp = Color(red: 0.62, green: 0.30, blue: 1.0)
    static let panel = Color(red: 0.055, green: 0.03, blue: 0.094)
}

@main
struct VynoxApp: App {
    @StateObject private var store = Store()
    @StateObject private var player = Player()

    var body: some Scene {
        WindowGroup {
            TabView {
                SearchView()
                    .tabItem { Label("Suchen", systemImage: "magnifyingglass") }
                LibraryView()
                    .tabItem { Label("Bibliothek", systemImage: "arrow.down.circle.fill") }
            }
            .environmentObject(store)
            .environmentObject(player)
            .preferredColorScheme(.dark)
            .tint(.vp)
        }
    }
}
