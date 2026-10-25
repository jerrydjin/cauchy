import AppKit
import SwiftUI

/// ImageRenderer draws neither `TextField` nor the contents of a `ScrollView`.
/// The designer snapshot sets this so the find bar and jump list still paint.
private struct RendersForSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var rendersForSnapshot: Bool {
        get { self[RendersForSnapshotKey.self] }
        set { self[RendersForSnapshotKey.self] = newValue }
    }
}

struct FindBarView: View {
    @Bindable var find: PDFFindModel
    @FocusState private var isFieldFocused: Bool
    @Environment(\.rendersForSnapshot) private var rendersForSnapshot

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

            if rendersForSnapshot {
                SnapshotFieldText(text: find.query, placeholder: "Find in document")
                    .frame(width: 200, alignment: .leading)
            } else {
                TextField("Find in document", text: $find.query)
                    .textFieldStyle(.plain)
                    .frame(width: 200)
                    .focused($isFieldFocused)
                    .onSubmit { find.findNext() }
            }

            if !find.query.isEmpty {
                Text(DocumentFind.textMatchLabel(count: find.matchCount, isSearching: find.isSearching))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Divider()
                .frame(height: 16)

            if rendersForSnapshot {
                SnapshotIcon(systemName: "chevron.up")
                SnapshotIcon(systemName: "chevron.down")
                SnapshotIcon(systemName: "xmark")
            } else {
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .modifier(FindCapsuleChrome(snapshot: rendersForSnapshot))
    }
}

/// ImageRenderer drops `glassEffect`, and the find bar with it. The snapshot
/// uses an opaque capsule; the live bar stays glass.
private struct FindCapsuleChrome: ViewModifier {
    var snapshot: Bool

    func body(content: Content) -> some View {
        Group {
            if snapshot {
                content
                    .background(.background, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    }
            } else {
                content.glassEffect(in: .capsule)
            }
        }
    }
}

private struct SnapshotIcon: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
    }
}

/// Layout contract for the Cmd-K panel. Jony, Cauchy room 2026-10-25: the
/// results area keeps one reserved height and scrolls inside it. The glass
/// chrome does not grow, shrink, or animate when the match count changes.
enum JumpPaletteMetrics {
    /// The old cap (`maxHeight: 420`) is now the reserved height. Short result
    /// lists leave empty glass below the rows instead of pulling the field down.
    static let resultsAreaHeight: CGFloat = 420
    /// Selected and hovered rows use this fill. One state, not two treatments.
    static let rowHighlightOpacity: Double = 0.14
    /// There is no animate-once path. Height does not follow the hit count.
    static let animatesResultsHeight = false

    static func resultsFrameHeight(hitCount: Int) -> CGFloat {
        _ = hitCount
        return resultsAreaHeight
    }

    static func rowIsHighlighted(isSelected: Bool, isHovered: Bool) -> Bool {
        isSelected || isHovered
    }
}

/// Centred Cmd-K catalogue. One layout in both appearances: Liquid Glass over
/// the page, light frost when the window is light and darker glass when it is
/// dark. Rows stay a label, an optional name, a page, and one preview line.
struct JumpPaletteView: View {
    @Bindable var palette: JumpPaletteModel
    var isIndexing: Bool = false
    @FocusState private var isFieldFocused: Bool
    @Environment(\.rendersForSnapshot) private var rendersForSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            Divider()
            results
        }
        .frame(width: 340)
        // Match-count changes must not animate the panel. The results frame is
        // reserved, and this opts that update out of any inherited animation.
        .animation(nil, value: palette.hits.count)
        .modifier(JumpPaletteChrome(snapshot: rendersForSnapshot))
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
            if rendersForSnapshot {
                SnapshotFieldText(text: palette.query, placeholder: "Jump to a theorem, lemma or section")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
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

    /// ImageRenderer drops `ScrollView` contents, so the snapshot paints every
    /// row in a stack. The live palette always reserves `resultsAreaHeight`
    /// and scrolls inside that frame, including when there are no matches.
    @ViewBuilder
    private var results: some View {
        if rendersForSnapshot {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(groupedHits, id: \.title) { group in
                    groupHeader(group)
                    ForEach(group.hits) { hit in
                        paletteRow(hit)
                    }
                }
            }
            .padding(10)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    if palette.hits.isEmpty {
                        Text(emptyMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(groupedHits, id: \.title) { group in
                                groupHeader(group)
                                ForEach(group.hits) { hit in
                                    paletteRow(hit)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(
                    height: JumpPaletteMetrics.resultsFrameHeight(hitCount: palette.hits.count),
                    alignment: .top
                )
                .transaction { transaction in
                    transaction.disablesAnimations = true
                }
                .onChange(of: palette.selection) {
                    guard palette.hits.indices.contains(palette.selection) else { return }
                    proxy.scrollTo(palette.hits[palette.selection].id, anchor: .center)
                }
            }
        }
    }

    private func groupHeader(_ group: (title: String, hits: [DocumentFind.Hit])) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(group.title)
                .foregroundStyle(.secondary)
            Text(" \(group.hits.count)")
                .foregroundStyle(.tertiary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
    }

    private func paletteRow(_ hit: DocumentFind.Hit) -> some View {
        JumpPaletteRow(
            hit: hit,
            isSelected: isSelected(hit),
            tracksPointer: !rendersForSnapshot
        ) {
            palette.jump(hit)
        }
        .id(hit.id)
    }

    private func isSelected(_ hit: DocumentFind.Hit) -> Bool {
        palette.hits.indices.contains(palette.selection)
            && palette.hits[palette.selection].id == hit.id
    }

    private var emptyMessage: String {
        if isIndexing || palette.isIndexing { return "Indexing statements…" }
        if palette.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No indexed statements"
        }
        return "No matches"
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

/// One row in the jump list. Hover and keyboard selection share one fill.
/// SwiftUI hover inside `.glassEffect` over a PDF view does not fire on
/// macOS 27, so the row also installs an AppKit tracking area. Either source
/// can light the row; both use the same highlight.
private struct JumpPaletteRow: View {
    var hit: DocumentFind.Hit
    var isSelected: Bool
    var tracksPointer: Bool
    var onJump: () -> Void

    @State private var pointerHover = false
    @State private var trackingHover = false

    private var isHovered: Bool { pointerHover || trackingHover }

    var body: some View {
        let visible = DocumentFind.namesForDisplay(hit.nameCandidates)
        let highlighted = JumpPaletteMetrics.rowIsHighlighted(
            isSelected: isSelected,
            isHovered: isHovered
        )
        Button(action: onJump) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(hit.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(3)
                    if visible.names.isEmpty {
                        Spacer(minLength: 8)
                    } else {
                        FittingNames(
                            names: visible.names,
                            allowsTruncation: !visible.stoppedBeforeCutOff
                        )
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
            .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(highlighted ? JumpPaletteMetrics.rowHighlightOpacity : 0))
        }
        .onContinuousHover { phase in
            guard tracksPointer else { return }
            switch phase {
            case .active: pointerHover = true
            case .ended: pointerHover = false
            }
        }
        .overlay {
            if tracksPointer {
                JumpHoverTracker { trackingHover = $0 }
            }
        }
        .accessibilityLabel(accessibilityLabel(hit, visible: visible))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Speak the name the row actually draws, accents composed, when it has one.
    private func accessibilityLabel(_ hit: DocumentFind.Hit, visible: DocumentFind.VisibleNames) -> String {
        if let name = visible.names.first {
            return "\(hit.title) (\(name)), page \(hit.pageIndex + 1)"
        }
        return "\(hit.label), page \(hit.pageIndex + 1)"
    }
}

/// Pointer enter/exit for a jump row. `hitTest` returns nil so the SwiftUI
/// button keeps the click. Tracking areas are delivered from the window, which
/// still reaches this view when the glass material swallows SwiftUI hover.
private struct JumpHoverTracker: NSViewRepresentable {
    var onHover: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHover: onHover)
    }

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        context.coordinator.onHover = onHover
        nsView.coordinator = context.coordinator
    }

    final class Coordinator {
        var onHover: @MainActor (Bool) -> Void
        init(onHover: @escaping @MainActor (Bool) -> Void) {
            self.onHover = onHover
        }
    }

    final class TrackerView: NSView {
        var coordinator: Coordinator?
        private var lastHovered: Bool?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // `perform(afterDelay:)` stays on the main thread without capturing
            // this view in a sendable closure. Bounds are often empty during
            // the update that inserts the view; the next turn sees the real frame.
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            guard window != nil else {
                report(false)
                return
            }
            perform(#selector(syncHoverFromRunLoop), with: nil, afterDelay: 0)
        }

        override func mouseEntered(with event: NSEvent) {
            report(true)
        }

        override func mouseExited(with event: NSEvent) {
            report(false)
        }

        @objc private func syncHoverFromRunLoop() {
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            report(bounds.contains(point))
        }

        private func report(_ hovered: Bool) {
            guard lastHovered != hovered else { return }
            lastHovered = hovered
            MainActor.assumeIsolated {
                coordinator?.onHover(hovered)
            }
        }
    }
}

/// Liquid Glass panel. ImageRenderer drops `glassEffect` and would leave the
/// list floating with no chrome, so the snapshot paints a translucent frost
/// in the same shape. The live palette uses the platform glass and blurs the page.
private struct JumpPaletteChrome: ViewModifier {
    var snapshot: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    func body(content: Content) -> some View {
        Group {
            if snapshot {
                content
                    .background(snapshotFrost, in: shape)
                    .overlay {
                        shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.16), radius: 18, y: 8)
            } else {
                content
                    .glassEffect(.regular, in: shape)
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            }
        }
    }

    /// Light frost over light paper, darker glass over dark paper.
    /// Kept under fully opaque so a page colour behind the snapshot still tints it.
    private var snapshotFrost: Color {
        colorScheme == .dark
            ? Color(white: 0.28, opacity: 0.84)
            : Color(white: 1, opacity: 0.78)
    }
}

/// Plain stand-in for a text field. ImageRenderer leaves `TextField` blank.
private struct SnapshotFieldText: View {
    var text: String
    var placeholder: String

    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(.body)
            .foregroundStyle(text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
    }
}

/// Shows the longest real name that fits, then a shorter one, then a word prefix.
/// A phrase cut off mid-way is not truncated into; the row shows the label alone.
private struct FittingNames: View {
    var names: [String]
    var allowsTruncation: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if allowsTruncation {
                ForEach(Array(names.dropLast()), id: \.self) { name in
                    fullName(name)
                }
                if let last = names.last {
                    Text("(\(last))")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                ForEach(names, id: \.self) { name in
                    fullName(name)
                }
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.primary)
    }

    private func fullName(_ name: String) -> some View {
        Text("(\(name))")
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
