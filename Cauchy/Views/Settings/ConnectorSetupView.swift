import SwiftUI
import SwiftTerm

struct ConnectorSetupView: View {
    let connector: AssistantConnector
    var onConnected: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var setup = ConnectorSetupService.shared
    @State private var terminalID = UUID()

    private var step: Int {
        switch setup.phase {
        case .idle, .installing: 0
        case .signIn: 1
        case .failed: connector.resolvedBinaryURL == nil ? 0 : 1
        case .checking, .ready: 2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: connector.symbol)
                    .font(.title).frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect \(connector.name)").font(.title2.weight(.semibold))
                    Text("Your account. Ready to use in Cauchy.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                ForEach(Array(["Install", "Sign in", "Ready"].enumerated()), id: \.offset) { index, title in
                    Label(title, systemImage: index < step || setup.phase == .ready ? "checkmark.circle.fill" : "\(index + 1).circle")
                        .foregroundStyle(index <= step ? Color.accentColor : Color.secondary)
                    if index < 2 { Rectangle().fill(.quaternary).frame(height: 1) }
                }
            }
            .font(.callout.weight(.medium))

            Group {
                switch setup.phase {
                case .idle, .installing:
                    VStack(spacing: 14) {
                        ProgressView()
                        Text(setup.phase == .installing ? "Installing \(connector.name)…" : "Getting \(connector.name) ready…").font(.headline)
                        Text(setup.phase == .installing ? "Downloading the official installer. This may take a few minutes." : "Checking your existing installation and sign-in.")
                            .foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 280)
                case .ready:
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green)
                        Text("\(connector.name) is connected").font(.title2.weight(.semibold))
                        Text("You can now use it to ask about your reading.").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 280)
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        Text(connector.resolvedBinaryURL == nil ? "Installation must finish before you can sign in." : "Follow \(connector.vendor)’s sign-in below. Your browser may open to approve access.")
                            .foregroundStyle(.secondary)
                        if let binary = connector.resolvedBinaryURL {
                            ConnectorSignInTerminal(binary: binary, arguments: setup.loginArguments) { exitCode in
                                if exitCode == 0 && setup.phase == .signIn && !setup.loginArguments.isEmpty {
                                    setup.check()
                                }
                            }
                            .id(terminalID)
                            .frame(height: 290)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                        }
                        if case .failed = setup.phase {
                            Text(connector.resolvedBinaryURL == nil ? "We couldn’t install \(connector.name). Retry installation to continue." : "We couldn’t verify the connection. Finish signing in and try again.")
                                .foregroundStyle(.orange)
                            DisclosureGroup("Details") {
                                if case .failed(let message) = setup.phase {
                                    Text(message).font(.caption).textSelection(.enabled).lineLimit(5)
                                }
                            }
                        }
                        if connector.resolvedBinaryURL != nil && (connector.id == .antigravity || setup.loginArguments.isEmpty) {
                            Text("Check connection sends a tiny test message using your plan. No document is shared.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                if setup.phase == .ready {
                    Button("Done") { dismiss() }
                } else {
                    Button("Cancel") { setup.cancel(); dismiss() }
                        .disabled(setup.phase == .installing)
                }
                Spacer()
                if setup.phase == .ready {
                    Button("Use \(connector.name)") {
                        AssistantPreferences.selection = .connector(connector.id)
                        onConnected()
                        dismiss()
                    }.buttonStyle(.borderedProminent)
                } else if setup.phase != .installing && setup.phase != .idle {
                    Button(connector.resolvedBinaryURL == nil ? "Retry installation" : "Restart sign-in") {
                        setup.begin(connector.id)
                        terminalID = UUID()
                    }.disabled(setup.busy)
                    Button {
                        setup.check()
                    } label: {
                        HStack {
                            if setup.phase == .checking { ProgressView().controlSize(.small) }
                            Text(setup.phase == .checking ? "Checking…" : "Check connection")
                        }
                    }.buttonStyle(.borderedProminent).disabled(setup.busy || connector.resolvedBinaryURL == nil)
                }
            }
        }
        .padding(28)
        .frame(width: 680, height: 590)
        .interactiveDismissDisabled(setup.busy)
        .onAppear { setup.begin(connector.id) }
        .onDisappear { setup.cancel(); onConnected() }
    }
}

/// A real PTY preserves browser callbacks and provider prompts, including older CLIs.
/// No shell command is constructed and no credential transcript is persisted.
private struct ConnectorSignInTerminal: NSViewRepresentable {
    let binary: URL
    let arguments: [String]
    let onExit: (Int32?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onExit: onExit) }
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 624, height: 290))
        view.processDelegate = context.coordinator
        var environment = CLIAgentRunner.environment
        environment["TERM"] = "xterm-256color"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cauchy-signin-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            context.coordinator.directory = directory
            view.startProcess(executable: binary.path, args: arguments,
                              environment: environment.map { "\($0.key)=\($0.value)" },
                              currentDirectory: directory.path)
        } catch {
            view.feed(text: "Could not start sign-in. Please close this window and try again.")
        }
        return view
    }
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.processDelegate = nil
        nsView.terminate()
        if let directory = coordinator.directory { try? FileManager.default.removeItem(at: directory) }
    }
    final class Coordinator: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
        let onExit: (Int32?) -> Void
        var directory: URL?
        init(onExit: @escaping (Int32?) -> Void) { self.onExit = onExit }
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) { onExit(exitCode) }
    }
}
