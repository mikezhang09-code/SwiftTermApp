//
//  AiExplainView.swift
//  SwiftTermApp
//
//  "Explain this" sheet: takes the terminal selection (or the tail of the
//  buffer), shows exactly what will be sent after redaction, and only sends
//  when the user taps Send.  The answer streams in from the active provider.
//

import SwiftUI
import SwiftTerm

struct AiExplainView: View {
    var terminalGetter: () -> AppTerminalView?
    @ObservedObject var store = AiProviderStore.shared
    @Environment (\.presentationMode) var presentationMode

    /// How many trailing buffer lines to send when there is no selection
    static let contextLines = 80

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

    static let systemPrompt = """
        You are an expert systems administrator built into an iOS SSH client. \
        The user sends you terminal output, possibly with sensitive values \
        replaced by placeholders like [IP-1] or [SECRET-1]; refer to the \
        placeholders as-is.  Explain what the output shows, and when it \
        contains errors, give the likely cause and a concrete fix.  Be \
        concise and answer in the language the user's question is written in \
        (default to the language of the output otherwise).
        """

    var redaction: RedactionResult {
        Redactor.redact (source)
    }

    var textToSend: String {
        redactEnabled ? redaction.text : source
    }

    var body: some View {
        NavigationView {
            Form {
                Section (header: Text (usedSelection ? "Selection" : "Last \(AiExplainView.contextLines) lines"),
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
                    TextField ("Explain this output", text: $question)
                }
                Section {
                    if let provider = store.active {
                        Button (action: send) {
                            HStack {
                                Label (phase == .streaming ? "Asking…" : "Send to \(provider.name)", systemImage: "paperplane")
                                Spacer ()
                                if phase == .streaming {
                                    ProgressView ()
                                }
                            }
                        }
                        .disabled (phase == .streaming || textToSend.isEmpty)
                        Text ("\(provider.kind.displayName) · \(provider.model).  Nothing is sent until you tap Send.")
                            .font (.caption)
                            .foregroundColor (.secondary)
                    } else {
                        Text ("No active AI provider — configure one under Home → AI")
                            .foregroundColor (.secondary)
                    }
                }
                if !answer.isEmpty || phase == .streaming {
                    Section (header: Text ("Answer")) {
                        Text (answer.isEmpty ? "…" : answer)
                            .font (.callout)
                            .textSelection2 ()
                            .frame (maxWidth: .infinity, alignment: .leading)
                    }
                }
                if case .failed (let message) = phase {
                    Section {
                        Label (message, systemImage: "xmark.circle.fill")
                            .foregroundColor (.red)
                            .font (.caption)
                    }
                }
            }
            .navigationTitle ("Explain")
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .cancellationAction) {
                    Button (phase == .streaming ? "Stop" : "Done") {
                        if phase == .streaming {
                            stream?.cancel ()
                            stream = nil
                            phase = .done
                        } else {
                            presentationMode.wrappedValue.dismiss ()
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
        source = trimmed.suffix (AiExplainView.contextLines).joined (separator: "\n")
        usedSelection = false
    }

    func send () {
        guard let provider = store.active else { return }
        let client = AiClient (config: provider, apiKey: store.apiKey (for: provider))
        let prompt = (question.isEmpty ? "Explain this terminal output." : question)
            + "\n\nTerminal output:\n```\n" + textToSend + "\n```"
        answer = ""
        phase = .streaming
        stream = client.chat (system: AiExplainView.systemPrompt, user: prompt, onDelta: { delta in
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
