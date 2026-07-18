//
//  AiCommandView.swift
//  SwiftTermApp
//
//  NL→shell: the user describes what they want, the provider returns one
//  command with a risk annotation, and nothing reaches the terminal until
//  the user explicitly inserts it.  Insertion never appends a newline —
//  the user always presses return themselves.
//

import SwiftUI
import SwiftTerm

/// The parsed provider answer
struct AiCommandSuggestion {
    var command: String
    var explanation: String
    var risk: Risk
    var riskReason: String

    enum Risk: String {
        case safe
        case caution
        case destructive

        var color: SwiftUI.Color {
            switch self {
            case .safe: return .green
            case .caution: return .orange
            case .destructive: return .red
            }
        }

        var label: String {
            switch self {
            case .safe: return "Safe"
            case .caution: return "Caution"
            case .destructive: return "Destructive"
            }
        }
    }

    /// Lenient parse: accepts surrounding prose/code fences around the JSON object
    static func parse (_ text: String) -> AiCommandSuggestion? {
        guard let start = text.firstIndex (of: "{"), let end = text.lastIndex (of: "}"), start < end else {
            return nil
        }
        let jsonText = String (text [start...end])
        guard let json = try? JSONSerialization.jsonObject (with: Data (jsonText.utf8)) as? [String: Any],
              let command = json ["command"] as? String else {
            return nil
        }
        return AiCommandSuggestion (
            command: command,
            explanation: json ["explanation"] as? String ?? "",
            risk: Risk (rawValue: (json ["risk"] as? String ?? "").lowercased ()) ?? .caution,
            riskReason: json ["risk_reason"] as? String ?? "")
    }
}

struct AiCommandView: View {
    var terminalGetter: () -> AppTerminalView?
    @ObservedObject var store = AiProviderStore.shared
    @Environment (\.presentationMode) var presentationMode

    @State var request = ""
    @State var includeContext = false
    @State var context = ""
    @State var running = false
    @State var suggestion: AiCommandSuggestion? = nil
    @State var rawAnswer = ""
    @State var errorMessage: String? = nil
    @State var confirmDestructive = false

    static func systemPrompt (language: AiAnswerLanguage) -> String {
        basePrompt + "  " + language.instruction
    }

    static let basePrompt = """
        You are an expert systems administrator built into an iOS SSH client. \
        The user describes what they want to do on a remote host; respond with \
        exactly one POSIX shell command that does it.  Respond with ONLY a JSON \
        object of this shape and nothing else: \
        {"command": "...", "explanation": "...", "risk": "safe|caution|destructive", "risk_reason": "..."} \
        Risk levels: "safe" reads state without changing it; "caution" changes \
        state reversibly or creates files; "destructive" deletes data, kills \
        processes, changes permissions broadly, or is hard to undo.  Prefer the \
        safest variant that satisfies the request (e.g. add -i to interactive \
        deletes).  If the request cannot be served with one command, set \
        "command" to "" and say why in "explanation".  Sensitive values in any \
        provided context appear as placeholders like [IP-1]; use the \
        placeholder verbatim if the command needs it.
        """

    var body: some View {
        NavigationView {
            Form {
                Section (header: Text ("What do you want to do?")) {
                    TextField ("e.g. find the 10 largest files under /var", text: $request)
                        .disableAutocorrection (true)
                }
                Section (footer: contextFooter) {
                    Toggle ("Include recent terminal output", isOn: $includeContext)
                    if includeContext && !context.isEmpty {
                        ScrollView {
                            Text (context)
                                .font (.system (.caption2, design: .monospaced))
                                .frame (maxWidth: .infinity, alignment: .leading)
                        }
                        .frame (maxHeight: 100)
                    }
                }
                Section {
                    if let provider = store.active {
                        Button (action: ask) {
                            HStack {
                                Label (running ? "Asking…" : "Get Command", systemImage: "wand.and.stars")
                                Spacer ()
                                if running {
                                    ProgressView ()
                                }
                            }
                        }
                        .disabled (running || request.isEmpty)
                        Text ("\(provider.kind.displayName) · \(provider.model)")
                            .font (.caption)
                            .foregroundColor (.secondary)
                    } else {
                        Text ("No active AI provider — configure one under Home → AI")
                            .foregroundColor (.secondary)
                    }
                }
                if let error = errorMessage {
                    Section {
                        Label (error, systemImage: "xmark.circle.fill")
                            .foregroundColor (.red)
                            .font (.caption)
                    }
                }
                if let suggestion = suggestion {
                    suggestionSection (suggestion)
                } else if !rawAnswer.isEmpty {
                    Section (header: Text ("Answer (could not parse a command)")) {
                        Text (rawAnswer)
                            .font (.caption)
                    }
                }
            }
            .navigationTitle ("Command")
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .cancellationAction) {
                    Button ("Done") {
                        presentationMode.wrappedValue.dismiss ()
                    }
                }
            }
            .onAppear (perform: captureContext)
            .alert (isPresented: $confirmDestructive) {
                Alert (title: Text ("Destructive command"),
                       message: Text (suggestion.map { "\($0.riskReason)\n\n\($0.command)" } ?? ""),
                       primaryButton: .destructive (Text ("Insert Anyway")) {
                           insert (force: true)
                       },
                       secondaryButton: .cancel ())
            }
        }
    }

    func suggestionSection (_ suggestion: AiCommandSuggestion) -> some View {
        Section (header: HStack {
            Text ("Suggested command")
            Spacer ()
            Text (suggestion.risk.label)
                .font (.caption2.bold ())
                .padding (.horizontal, 8)
                .padding (.vertical, 2)
                .background (suggestion.risk.color.opacity (0.2))
                .foregroundColor (suggestion.risk.color)
                .cornerRadius (6)
        }) {
            if suggestion.command.isEmpty {
                Text (suggestion.explanation.isEmpty ? "The provider could not suggest a command" : suggestion.explanation)
                    .font (.callout)
            } else {
                Text (suggestion.command)
                    .font (.system (.body, design: .monospaced))
                    .textSelection2 ()
                    .frame (maxWidth: .infinity, alignment: .leading)
                if !suggestion.explanation.isEmpty {
                    Text (suggestion.explanation)
                        .font (.caption)
                        .foregroundColor (.secondary)
                }
                if suggestion.risk != .safe && !suggestion.riskReason.isEmpty {
                    Text (suggestion.riskReason)
                        .font (.caption)
                        .foregroundColor (suggestion.risk.color)
                }
                Button (action: { insert (force: false) }) {
                    Label ("Insert into terminal", systemImage: "arrow.down.to.line")
                        .foregroundColor (suggestion.risk == .destructive ? .red : .accentColor)
                }
                Text ("The command is typed into the terminal but not run — press return yourself.")
                    .font (.caption2)
                    .foregroundColor (.secondary)
            }
        }
    }

    var contextFooter: some View {
        Group {
            if includeContext {
                Text ("The redacted output above is sent along with your request.")
            } else {
                Text ("Only your request text is sent.")
            }
        }
    }

    func captureContext () {
        guard context.isEmpty, let terminal = terminalGetter () else { return }
        let data = terminal.getTerminal ().getBufferAsData ()
        guard let full = String (bytes: data, encoding: .utf8) else { return }
        var lines = full.split (separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters (in: .whitespaces) }
        while let last = lines.last, last.isEmpty {
            lines.removeLast ()
        }
        context = Redactor.redact (lines.suffix (40).joined (separator: "\n")).text
    }

    func ask () {
        guard let provider = store.active else { return }
        let client = AiClient (config: provider, apiKey: store.apiKey (for: provider))
        var user = "Request: \(request)"
        if includeContext && !context.isEmpty {
            user += "\n\nRecent terminal output for context:\n```\n\(context)\n```"
        }
        running = true
        errorMessage = nil
        suggestion = nil
        rawAnswer = ""
        Task {
            do {
                let text = try await client.completeJson (
                    system: AiCommandView.systemPrompt (language: store.answerLanguage), user: user)
                await MainActor.run {
                    running = false
                    if let parsed = AiCommandSuggestion.parse (text) {
                        suggestion = parsed
                    } else {
                        rawAnswer = text
                    }
                }
            } catch {
                await MainActor.run {
                    running = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func insert (force: Bool) {
        guard let suggestion = suggestion, !suggestion.command.isEmpty else { return }
        if suggestion.risk == .destructive && !force {
            confirmDestructive = true
            return
        }
        guard let terminal = terminalGetter () else { return }
        // No trailing newline — the user reviews and presses return
        terminal.send (txt: suggestion.command)
        presentationMode.wrappedValue.dismiss ()
    }
}
