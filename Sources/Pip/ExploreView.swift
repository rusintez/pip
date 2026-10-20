import MusicKit
import SwiftUI

struct ExploreView: View {
    @Bindable var store: MusicStore
    @Binding var queueVisible: Bool
    @State private var source = ExploreSource.topSongs
    @State private var sections: [DiscoverySection] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshID = UUID()
    @State private var latestRequest = LatestRequest()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Picker("Browse", selection: $source) {
                    ForEach(ExploreSource.allCases) { source in Text(source.rawValue).tag(source) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
                if source != .personal {
                    Menu(store.iTunesCountry) {
                        Picker("Store country", selection: $store.iTunesCountry) {
                            ForEach(ITunesSearch.countries, id: \.self) { country in
                                Text(Locale.current.localizedString(forRegionCode: country) ?? country).tag(country)
                            }
                        }
                    }
                    .fixedSize()
                    .help("Choose the country for charts and featured music")
                    .accessibilityLabel("Explore country: \(store.iTunesCountry)")
                }
                Button { refreshID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .disabled(isLoading)
                    .help("Refresh Explore")
                    .accessibilityLabel("Refresh Explore")
            }
            .padding(.horizontal, 28)
            .frame(height: 66)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text(source.rawValue).font(.system(size: 29, weight: .bold))
                Text(source == .personal ? "Picked for your Apple Music account."
                     : "Apple Music · \(Locale.current.localizedString(forRegionCode: store.iTunesCountry) ?? store.iTunesCountry)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .padding(28)

            if isLoading {
                ProgressView("Loading \(source.rawValue.lowercased())…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label(source == .personal ? "Recommendations unavailable" : "Couldn’t load this collection", systemImage: "exclamationmark.circle")
                } description: { Text(errorMessage) } actions: {
                    Button("Retry") { refreshID = UUID() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sections.isEmpty {
                ContentUnavailableView("Nothing here yet", systemImage: "music.note.list",
                    description: Text(source == .personal ? "Apple hasn’t returned any recommendations yet. Try again later."
                                      : "Try another country or refresh this collection."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    Task {
                                        await store.playDiscovery(item, among: section.items)
                                        if store.errorMessage == nil, case .playlist = item { queueVisible = true }
                                        if store.errorMessage == nil, case .album = item { queueVisible = true }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        if source == .topSongs || source == .playlists {
                                            Text("\(index + 1)").font(.system(size: 12).monospacedDigit())
                                                .foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                                        }
                                        TrackTile(artwork: item.artwork)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title).foregroundStyle(.primary)
                                            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                        }
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "play.circle").foregroundStyle(Palette.accent)
                                    }
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isControlling)
                                .accessibilityLabel("Play \(item.title) by \(item.subtitle)")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .padding(.horizontal, 12)
            }
        }
        .task(id: "\(source.rawValue):\(store.iTunesCountry):\(refreshID)") {
            let request = latestRequest.begin()
            isLoading = true
            errorMessage = nil
            sections = []
            defer { if latestRequest.isCurrent(request) { isLoading = false } }
            do {
                let result = try await MusicDiscovery.sections(source: source, country: store.iTunesCountry)
                try Task.checkCancellation()
                if latestRequest.isCurrent(request) { sections = result }
            } catch {
                if latestRequest.isCurrent(request), !Task.isCancelled {
                    errorMessage = MusicDiscovery.message(for: error, source: source)
                }
            }
        }
    }
}
