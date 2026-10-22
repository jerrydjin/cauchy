import SwiftUI

struct FindBarView: View {
    @Bindable var find: PDFFindModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            capsule
            if !find.namedHits.isEmpty {
                namedList
            }
        }
        .onExitCommand { find.dismiss() }
        .onAppear { isFieldFocused = true }
        .onChange(of: find.focusRequest) {
            isFieldFocused = true
        }
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Find in document", text: $find.query)
                .textFieldStyle(.plain)
                .frame(width: 200)
                .focused($isFieldFocused)
                .onSubmit { submit() }

            if !find.query.isEmpty {
                Text(matchLabel)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Divider()
                .frame(height: 16)

            GlassIconButton(systemName: "chevron.up", accessibilityLabel: "Previous Match") {
                find.findPrevious()
            }
            .disabled(!find.hasMatches)

            GlassIconButton(systemName: "chevron.down", accessibilityLabel: "Next Match") {
                find.findNext()
            }
            .disabled(!find.hasMatches)

            GlassIconButton(systemName: "xmark", accessibilityLabel: "Close Find Bar") {
                find.dismiss()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
    }

    private var namedList: some View {
        let groups = groupedHits
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(groups, id: \.title) { group in
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(group.hits) { hit in
                    Button {
                        find.activate(hit)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(hit.label)
                                    .font(.callout.weight(.medium))
                                Spacer(minLength: 8)
                                Text("p. \(hit.pageIndex + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if !hit.firstLine.isEmpty {
                                Text(hit.firstLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .glassEffect(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var groupedHits: [(title: String, hits: [DocumentFind.Hit])] {
        var titles: [String] = []
        var grouped: [String: [DocumentFind.Hit]] = [:]
        for hit in find.namedHits {
            if grouped[hit.group] == nil { titles.append(hit.group) }
            grouped[hit.group, default: []].append(hit)
        }
        return titles.map { ($0, grouped[$0] ?? []) }
    }

    private var matchLabel: String {
        if let message = find.namedMissMessage { return message }
        if find.isSearching { return "Searching…" }
        if !find.namedHits.isEmpty && find.currentIndex == nil {
            if find.matches.isEmpty { return "\(find.namedHits.count) named" }
            return "\(find.namedHits.count) named, \(find.matches.count) text"
        }
        guard find.hasMatches else { return "Not found" }
        let position = (find.currentIndex ?? 0) + 1
        return "\(position) of \(find.matches.count)"
    }

    private func submit() {
        if find.namedMissMessage != nil { return }
        if find.namedHits.count == 1 && find.matches.isEmpty {
            find.activate(find.namedHits[0])
            return
        }
        if find.namedHits.count > 1 && find.matches.isEmpty {
            return
        }
        find.findNext()
    }
}
