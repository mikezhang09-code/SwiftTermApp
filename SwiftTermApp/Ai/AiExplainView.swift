//
//  AiExplainView.swift
//  SwiftTermApp
//
//  "Explain this" / "Diagnose" sheet: takes the terminal selection (or the
//  tail of the buffer), shows exactly what will be sent after redaction, and
//  only sends when the user taps Send.  The answer streams in from the active
//  provider.  The two modes differ in scrollback size and system prompt.
//

import SwiftUI
import SwiftTerm

struct AiExplainView: View {
    var terminalGetter: () -> AppTerminalView?
    var mode: Mode = .explain
    @ObservedObject var store = AiProviderStore.shared
    @Environment (\.presentationMode) var presentationMode

    /// What the sheet is being used for.  Both modes share the capture,
    /// redaction, preview and streaming machinery; they differ in how much
    /// context they grab and what they ask the model for.
    enum Mode {
        case explain
        case diagnose

        var title: String {
            switch self {
            case .explain: return "Explain"
            case .diagnose: return "Diagnose"
            }
        }

        /// Diagnosis needs more scrollback: the failure is usually several
        /// commands back from the last prompt
        var contextLines: Int {
            switch self {
            case .explain: return 80
            case .diagnose: return 150
            }
        }

        var questionPlaceholder: String {
            switch self {
            case .explain: return "Explain this output"
            case .diagnose: return "What went wrong and how do I fix it?"
            }
        }

        var defaultPrompt: String {
            switch self {
            case .explain: return "Explain this terminal output."
            case .diagnose: return "Something went wrong here.  Diagnose it."
            }
        }

        var systemPrompt: String {
            let shared = """
                You are an expert systems administrator built into an iOS SSH \
                client.  The user sends you terminal output, possibly with \
                sensitive values replaced by placeholders like [IP-1] or \
                [SECRET-1]; refer to the placeholders as-is and never ask for \
                the real values.  Answer in the language the user's question is \
                written in, defaulting to the language of the output.
                """
            switch self {
            case .explain:
                return shared + """
                     Explain what the output shows, and when it contains \
                    errors, give the likely cause and a concrete fix.  Be concise.
                    """
            case .diagnose:
                return shared + """
                     The output contains a failure.  Structure your answer as: \
                    (1) what failed — quote the key line; (2) the most likely \
                    cause, and say plainly when you are inferring rather than \
                    certain; (3) a concrete next step, as a command to run when \
                    one applies.  If several causes are plausible, give the \
                    check that distinguishes them rather than guessing.  If the \
                    output contains no failure, say so instead of inventing one.
                    """
            }
        }
    }

    @State var source = ""
    @State var usedSelection = false
    @State var redactEnabled = true
    @State var question = ""
    @State var answer = ""
    @State var phase: Phase = .preview
    @State var stream: AiChatStream? = nil

    enum Phase: Equatable {
        case preview
        case streaming
        case done
        case failed (String)
    }

    var redaction: RedactionResult {
        Redactor.redact (source)
    }

    var textToSend: String {
        redactEnabled ? redaction.text : source
    }

    var body: some View {
        NavigationView {
            Group {
                if phase == .preview {
                    previewForm
                } else {
                    answerScreen
                }
            }
            .navigationTitle (mode.title)
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .cancellationAction) {
                    Button ("Done") {
                        stream?.cancel ()
                        presentationMode.wrappedValue.dismiss ()
                    }
                }
                ToolbarItem (placement: .confirmationAction) {
                    if phase == .streaming {
                        Button ("Stop") {
                            stream?.cancel ()
                            stream = nil
                            phase = .done
                        }
                    } else if phase != .preview {
                        Button ("Ask Again") {
                            phase = .preview
                        }
                    }
                }
            }
            .onAppear (perform: capture)
            .onDisappear {
                stream?.cancel ()
            }
        }
    }

    // MARK: preview phase — nothing is sent from this screen except via Send

    var previewForm: some View {
        Form {
            Section (header: Text (usedSelection ? "Selection" : "Last \(mode.contextLines) lines"),
                     footer: redactionFooter) {
                ScrollView {
                    Text (textToSend.isEmpty ? "Nothing captured from the terminal" : textToSend)
                        .font (.system (.caption2, design: .monospaced))
                        .frame (maxWidth: .infinity, alignment: .leading)
                }
                .frame (maxHeight: 160)
                Toggle ("Redact sensitive values", isOn: $redactEnabled)
            }
            Section (header: Text ("Question (optional)")) {
                TextField (mode.questionPlaceholder, text: $question)
            }
            Section {
                if let provider = store.active {
                    Button (action: send) {
                        Label ("Send to \(provider.name)", systemImage: "paperplane")
                    }
                    .disabled (textToSend.isEmpty)
                    Text ("\(provider.kind.displayName) · \(provider.model).  Nothing is sent until you tap Send.")
                        .font (.caption)
                        .foregroundColor (.secondary)
                } else {
                    Text ("No active AI provider — configure one under Home → AI")
                        .foregroundColor (.secondary)
                }
            }
        }
    }

    // MARK: answer phase — the whole screen is the streamed answer

    var answerScreen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack (alignment: .leading, spacing: 12) {
                    Text (question.isEmpty ? mode.defaultPrompt : question)
                        .font (.caption)
                        .foregroundColor (.secondary)
                    if case .failed (let message) = phase {
                        Label (message, systemImage: "xmark.circle.fill")
                            .foregroundColor (.red)
                    }
                    if answer.isEmpty && phase == .streaming {
                        HStack (spacing: 8) {
                            ProgressView ()
                            Text ("Waiting for \(store.active?.name ?? "provider")…")
                                .foregroundColor (.secondary)
                        }
                    } else {
                        Text (answer)
                            .font (.callout)
                            .textSelection2 ()
                            .frame (maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame (height: 1).id ("bottom")
                }
                .padding ()
            }
            .onChange (of: answer) { _ in
                if phase == .streaming {
                    proxy.scrollTo ("bottom", anchor: .bottom)
                }
            }
        }
    }

    var redactionFooter: some View {
        Group {
            if redactEnabled {
                Text (redaction.summary + ".  Redaction is best-effort — review the text above before sending.")
            } else {
                Text ("Redaction is off — the text above is sent verbatim.")
            }
        }
    }

    func capture () {
        guard source.isEmpty, let terminal = terminalGetter () else { return }
        if let selection = terminal.getSelection (), !selection.isEmpty {
            source = selection
            usedSelection = true
            return
        }
        let data = terminal.getTerminal ().getBufferAsData ()
        guard let full = String (bytes: data, encoding: .utf8) else { return }
        let lines = full.split (separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters (in: .whitespaces) }
        // Drop the trailing run of blank rows that pads the buffer
        var trimmed = lines
        while let last = trimmed.last, last.isEmpty {
            trimmed.removeLast ()
        }
        source = trimmed.suffix (mode.contextLines).joined (separator: "\n")
        usedSelection = false
    }

    func send () {
        guard let provider = store.active else { return }
        let client = AiClient (config: provider, apiKey: store.apiKey (for: provider))
        let prompt = (question.isEmpty ? mode.defaultPrompt : question)
            + "\n\nTerminal output:\n```\n" + textToSend + "\n```"
        answer = ""
        phase = .streaming
        stream = client.chat (system: mode.systemPrompt, user: prompt, onDelta: { delta in
            answer += delta
        }, onDone: { result in
            switch result {
            case .success:
                phase = .done
            case .failure (let error):
                // Cancelling mid-stream surfaces as NSURLErrorCancelled — not a failure
                if (error as NSError).code == NSURLErrorCancelled {
                    phase = .done
                } else {
                    phase = .failed (error.localizedDescription)
                }
            }
            stream = nil
        })
    }
}

extension Text {
    /// .textSelection(.enabled) is iOS 15+, the app still targets 14.7
    @ViewBuilder
    func textSelection2 () -> some View {
        if #available (iOS 15.0, *) {
            self.textSelection (.enabled)
        } else {
            self
        }
    }
}
