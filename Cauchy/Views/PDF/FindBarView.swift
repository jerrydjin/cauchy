import SwiftUI

struct FindBarView: View {
    @Bindable var find: PDFFindModel
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        capsule
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
                .onSubmit { find.findNext() }

            if !find.query.isEmpty {
                Text(DocumentFind.textMatchLabel(count: find.matchCount, isSearching: find.isSearching))
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
}

/// Centred Cmd-K catalogue. Opaque window background, so the page doesn't show through.
struct JumpPaletteView: View {
    @Bindable var palette: JumpPaletteModel
    var isIndexing: Bool = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            Divider()
            results
        }
        .frame(width: 340)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onExitCommand { palette.dismiss() }
        .onAppear { isFieldFocused = true }
        .onChange(of: palette.focusRequest) {
            isFieldFocused = true
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(.secondary)
            TextField("Jump to a theorem, lemma or section", text: $palette.query)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .onSubmit { palette.jumpSelected() }
                .onKeyPress(keys: [.upArrow, .downArrow, .escape], phases: .down) { key in
                    switch key.key {
                    case .upArrow: palette.move(-1)
                    case .downArrow: palette.move(1)
                    case .escape: palette.dismiss()
                    default: break
                    }
                    return .handled
                }
            if !palette.query.isEmpty {
                Button {
                    palette.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Jump Query")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var results: some View {
        if palette.hits.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedHits, id: \.title) { group in
                            Text("\(group.title) \(group.hits.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                            ForEach(group.hits) { hit in
                                row(hit)
                                    .id(hit.id)
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 420)
                .onChange(of: palette.selection) {
                    guard palette.hits.indices.contains(palette.selection) else { return }
                    proxy.scrollTo(palette.hits[palette.selection].id, anchor: .center)
                }
            }
        }
    }

    private var emptyMessage: String {
        if isIndexing || palette.isIndexing { return "Indexing statements…" }
        if palette.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No indexed statements"
        }
        return "No matches"
    }

    private func row(_ hit: DocumentFind.Hit) -> some View {
        let selected = palette.hits.indices.contains(palette.selection)
            && palette.hits[palette.selection].id == hit.id
        return Button {
            palette.jump(hit)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hit.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(3)
                    if hit.nameCandidates.isEmpty {
                        Spacer(minLength: 8)
                    } else {
                        FittingNames(names: hit.nameCandidates)
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                    }
                    Text("p. \(hit.pageIndex + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(3)
                }
                if !hit.firstLine.isEmpty {
                    Text(hit.firstLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hit.label), page \(hit.pageIndex + 1)")
    }

    private var groupedHits: [(title: String, hits: [DocumentFind.Hit])] {
        var titles: [String] = []
        var grouped: [String: [DocumentFind.Hit]] = [:]
        for hit in palette.hits {
            if grouped[hit.group] == nil { titles.append(hit.group) }
            grouped[hit.group, default: []].append(hit)
        }
        return titles.map { ($0, grouped[$0] ?? []) }
    }
}

/// Shows the longest real name that fits, then a shorter one, then a word prefix.
private struct FittingNames: View {
    var names: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Array(names.dropLast()), id: \.self) { name in
                Text("(\(name))")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let last = names.last {
                Text("(\(last))")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
    }
}
