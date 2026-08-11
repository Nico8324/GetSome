/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A view that lists the categories a source publishes.
*/

import SwiftUI

/// A view that lists the categories a source publishes.
///
/// A site can publish thousands of these — xvideos lists around two thousand — so
/// they're fetched once, filtered in place, and never turned into tabs.
struct CategoriesView: View {
    let sourceID: String
    let namespace: Namespace.ID

    @State private var categories = [Feed]()
    @State private var query = ""
    @State private var isLoading = false
    @State private var error: String?

    private var source: (any ContentSource)? {
        ContentSources.source(with: sourceID)
    }

    private var filtered: [Feed] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            if let error {
                Section {
                    VStack(alignment: .leading, spacing: Constants.genreSpacing) {
                        Text("Couldn’t load categories")
                            .font(.headline)
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Try Again") {
                            Task { await load(force: true) }
                        }
                    }
                }
            }

            ForEach(filtered) { category in
                NavigationLink {
                    // Already inside a navigation stack, so this one mustn't make
                    // its own.
                    FeedView(feed: category, namespace: namespace, isRoot: false)
                } label: {
                    LabeledContent(category.name, value: category.description)
                }
            }
        }
        .navigationTitle("Categories")
        #if !os(tvOS)
        .searchable(text: $query, prompt: Text("Filter categories"))
        #endif
        .overlay {
            if isLoading && categories.isEmpty {
                ProgressView()
            } else if !isLoading && categories.isEmpty && error == nil {
                ContentUnavailableView(
                    "No categories",
                    systemImage: "tag",
                    description: Text("\(source?.displayName ?? "This site") doesn’t publish a category list.")
                )
            } else if filtered.isEmpty && !query.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        guard categories.isEmpty || force else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            categories = try await ContentClient.shared.categories(for: sourceID)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview(traits: .previewData) {
    @Previewable @Namespace var namespace
    return NavigationStack {
        CategoriesView(sourceID: ContentSources.all[0].id, namespace: namespace)
    }
}
