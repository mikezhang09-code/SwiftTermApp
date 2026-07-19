//
//  HelpView.swift
//  SwiftTermApp
//
//  The Help hub: the user guide and the command reference.
//

import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            Section (header: Text ("User Guide"),
                     footer: Text ("How to use the app, from adding a host to tunnelling a port.")) {
                ForEach (userGuideTopics) { topic in
                    NavigationLink (destination: GuideTopicView (topic: topic)) {
                        Label {
                            VStack (alignment: .leading, spacing: 2) {
                                Text (topic.title)
                                Text (topic.summary)
                                    .font (.caption)
                                    .foregroundColor (.secondary)
                            }
                        } icon: {
                            Image (systemName: topic.icon)
                        }
                    }
                }
            }

            Section (header: Text ("Reference")) {
                NavigationLink (destination: CommandReferenceView ()) {
                    Label {
                        VStack (alignment: .leading, spacing: 2) {
                            Text ("Command Reference")
                            Text ("Common Linux, macOS and PowerShell commands")
                                .font (.caption)
                                .foregroundColor (.secondary)
                        }
                    } icon: {
                        Image (systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
        .listStyle (GroupedListStyle ())
        .navigationTitle ("Help")
    }
}

struct GuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
        ScrollView {
            VStack (alignment: .leading, spacing: 24) {
                ForEach (topic.sections) { section in
                    VStack (alignment: .leading, spacing: 12) {
                        Text (section.heading)
                            .font (.headline)
                        ForEach (section.blocks) { block in
                            GuideBlockView (block: block)
                        }
                    }
                }
            }
            .padding ()
            .frame (maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle (topic.title)
        .navigationBarTitleDisplayMode (.inline)
    }
}

/// Builds a `Text` from a string that may contain `{symbolname}` tokens,
/// substituting the live SF Symbol.  Using the real symbol means the icon in
/// the guide is always the icon in the toolbar — a screenshot would drift the
/// moment the UI changed, and would have to be redone per device and language.
func helpTextWithSymbols (_ source: String) -> Text {
    var result = Text ("")
    var remainder = Substring (source)

    while let open = remainder.firstIndex (of: "{"),
          let close = remainder [open...].firstIndex (of: "}") {
        let before = String (remainder [remainder.startIndex ..< open])
        let name = String (remainder [remainder.index (after: open) ..< close])

        if !before.isEmpty {
            result = result + Text (helpMarkdown (before))
        }
        // Only substitute names that resolve; otherwise show the literal text
        // so a typo is visible rather than silently swallowed.
        if UIImage (systemName: name) != nil {
            result = result + Text (Image (systemName: name)).foregroundColor (.accentColor)
        } else {
            result = result + Text ("{\(name)}")
        }
        remainder = remainder [remainder.index (after: close)...]
    }
    if !remainder.isEmpty {
        result = result + Text (helpMarkdown (String (remainder)))
    }
    return result
}

struct GuideBlockView: View {
    let block: GuideBlock

    var body: some View {
        switch block {
        case .prose (let text):
            helpTextWithSymbols (text)
                .font (.body)
                .fixedSize (horizontal: false, vertical: true)
                .frame (maxWidth: .infinity, alignment: .leading)

        case .steps (let items):
            VStack (alignment: .leading, spacing: 12) {
                ForEach (Array (items.enumerated ()), id: \.offset) { index, item in
                    HStack (alignment: .top, spacing: 12) {
                        Text ("\(index + 1)")
                            .font (.footnote.weight (.semibold))
                            .foregroundColor (.white)
                            .frame (width: 22, height: 22)
                            .background (Circle ().fill (Color.accentColor))
                        helpTextWithSymbols (item)
                            .font (.body)
                            .fixedSize (horizontal: false, vertical: true)
                            .frame (maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding (14)
            .frame (maxWidth: .infinity, alignment: .leading)
            .background (Color (.secondarySystemBackground))
            .cornerRadius (10)

        case .bullets (let items):
            VStack (alignment: .leading, spacing: 12) {
                ForEach (Array (items.enumerated ()), id: \.offset) { _, item in
                    helpTextWithSymbols (item)
                        .font (.body)
                        .fixedSize (horizontal: false, vertical: true)
                        .frame (maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding (14)
            .frame (maxWidth: .infinity, alignment: .leading)
            .background (Color (.secondarySystemBackground))
            .cornerRadius (10)

        case .terminal (let lines):
            // A miniature terminal, so command examples read the way they will
            // actually look on screen rather than as prose.
            VStack (alignment: .leading, spacing: 2) {
                ForEach (Array (lines.enumerated ()), id: \.offset) { _, line in
                    if line.hasPrefix ("$ ") {
                        (Text ("$ ").foregroundColor (.green)
                         + Text (String (line.dropFirst (2))).foregroundColor (.white))
                            .font (.system (.callout, design: .monospaced))
                            .fixedSize (horizontal: false, vertical: true)
                    } else {
                        Text (line)
                            .font (.system (.callout, design: .monospaced))
                            .foregroundColor (Color (white: 0.75))
                            .fixedSize (horizontal: false, vertical: true)
                    }
                }
            }
            .padding (12)
            .frame (maxWidth: .infinity, alignment: .leading)
            .background (Color.black)
            .cornerRadius (10)

        case .tip (let text):
            HStack (alignment: .top, spacing: 10) {
                Image (systemName: "lightbulb.fill")
                    .foregroundColor (.orange)
                helpTextWithSymbols (text)
                    .font (.callout)
                    .fixedSize (horizontal: false, vertical: true)
            }
            .padding (12)
            .frame (maxWidth: .infinity, alignment: .leading)
            .background (Color.orange.opacity (0.12))
            .cornerRadius (10)
        }
    }
}

struct CommandReferenceView: View {
    @State private var platform: CommandPlatform = .unix
    @State private var search: String = ""

    /// The groups for the current platform, with entries filtered by the search
    /// field.  Groups that end up empty are dropped so the list does not show
    /// bare headers.
    var visibleGroups: [CommandCategory] {
        let groups = commandGroups (for: platform)
        let needle = search.trimmingCharacters (in: .whitespaces).lowercased ()
        if needle.isEmpty {
            return groups
        }
        return groups.compactMap { group in
            let matches = group.entries.filter { $0.searchText.lowercased ().contains (needle) }
            return matches.isEmpty ? nil : CommandCategory (name: group.name, icon: group.icon,
                                                            intro: group.intro, entries: matches)
        }
    }

    var body: some View {
        VStack (spacing: 0) {
            Picker ("Platform", selection: $platform) {
                ForEach (CommandPlatform.allCases) { p in
                    Text (p.title).tag (p)
                }
            }
            .pickerStyle (SegmentedPickerStyle ())
            .padding ([.leading, .trailing, .bottom])

            List {
                if visibleGroups.isEmpty {
                    Text ("No commands match \"\(search)\"")
                        .foregroundColor (.secondary)
                } else {
                    ForEach (visibleGroups) { group in
                        Section {
                            ForEach (group.entries) { entry in
                                CommandRow (entry: entry)
                            }
                        } header: {
                            Label (group.name, systemImage: group.icon)
                        } footer: {
                            // Only worth showing when the whole group is on screen;
                            // during a search the intro describes commands that were
                            // filtered out.
                            if !group.intro.isEmpty && search.isEmpty {
                                Text (helpMarkdown (group.intro))
                                    .font (.caption)
                            }
                        }
                    }
                }
            }
            .listStyle (GroupedListStyle ())
        }
        .searchable (text: $search, prompt: "Search commands")
        .navigationTitle ("Commands")
        .navigationBarTitleDisplayMode (.inline)
    }
}

/// A terminal is only offered as an insert target when one is on screen;
/// reaching Help from the home screen usually means there is none.
private var activeTerminal: AppTerminalView? {
    TerminalViewController.visibleTerminal
}

private func copyToPasteboard (_ text: String) {
    UIPasteboard.general.string = text
}

/// Deliberately sends no trailing newline: the text lands at the prompt so it
/// can be read and edited before it runs.
private func insertInTerminal (_ text: String) {
    activeTerminal?.send (Array (text.utf8))
}

/// The shared Copy / Insert actions, used by both the list rows and the
/// examples on the detail page.
@ViewBuilder
private func commandActions (for text: String) -> some View {
    Button {
        copyToPasteboard (text)
    } label: {
        Label ("Copy", systemImage: "doc.on.doc")
    }
    if activeTerminal != nil {
        Button {
            insertInTerminal (text)
        } label: {
            Label ("Insert into Terminal", systemImage: "terminal")
        }
    }
}

struct CommandRow: View {
    let entry: CommandEntry

    var body: some View {
        NavigationLink (destination: CommandDetailView (entry: entry)) {
            VStack (alignment: .leading, spacing: 3) {
                Text (entry.command)
                    .font (.system (.body, design: .monospaced))
                Text (entry.summary)
                    .font (.caption)
                    .foregroundColor (.secondary)
                    .fixedSize (horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            commandActions (for: entry.command)
        }
    }
}

/// The explanation page for a single command: what it does, worked examples,
/// and the mistake people actually make with it.
struct CommandDetailView: View {
    let entry: CommandEntry
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack (alignment: .leading, spacing: 20) {
                // The command itself, with the actions right where you land
                VStack (alignment: .leading, spacing: 10) {
                    Text (entry.command)
                        .font (.system (.title3, design: .monospaced))
                        .textSelection (.enabled)
                        .fixedSize (horizontal: false, vertical: true)
                    Text (entry.summary)
                        .font (.subheadline)
                        .foregroundColor (.secondary)
                        .fixedSize (horizontal: false, vertical: true)
                    HStack (spacing: 12) {
                        Button {
                            copyToPasteboard (entry.command)
                            copied = true
                            DispatchQueue.main.asyncAfter (deadline: .now () + 1.2) { copied = false }
                        } label: {
                            Label (copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .font (.callout)
                        }
                        if activeTerminal != nil {
                            Button {
                                insertInTerminal (entry.command)
                            } label: {
                                Label ("Insert", systemImage: "terminal")
                                    .font (.callout)
                            }
                        }
                    }
                }
                .padding ()
                .frame (maxWidth: .infinity, alignment: .leading)
                .background (Color (.secondarySystemBackground))
                .cornerRadius (10)

                if !entry.detail.isEmpty {
                    VStack (alignment: .leading, spacing: 8) {
                        Text ("What it does")
                            .font (.headline)
                        Text (helpMarkdown (entry.detail))
                            .fixedSize (horizontal: false, vertical: true)
                    }
                }

                if !entry.examples.isEmpty {
                    VStack (alignment: .leading, spacing: 12) {
                        Text ("Examples")
                            .font (.headline)
                        ForEach (entry.examples) { example in
                            ExampleRow (example: example)
                        }
                    }
                }

                if let caution = entry.caution {
                    HStack (alignment: .top, spacing: 10) {
                        Image (systemName: "exclamationmark.triangle.fill")
                            .foregroundColor (.orange)
                        Text (helpMarkdown (caution))
                            .font (.callout)
                            .fixedSize (horizontal: false, vertical: true)
                    }
                    .padding ()
                    .frame (maxWidth: .infinity, alignment: .leading)
                    .background (Color.orange.opacity (0.12))
                    .cornerRadius (10)
                }
            }
            .padding ()
            .frame (maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle (entry.command)
        .navigationBarTitleDisplayMode (.inline)
    }
}

struct ExampleRow: View {
    let example: CommandExample

    var body: some View {
        VStack (alignment: .leading, spacing: 4) {
            Text (example.code)
                .font (.system (.callout, design: .monospaced))
                .textSelection (.enabled)
                .fixedSize (horizontal: false, vertical: true)
            Text (helpMarkdown (example.explanation))
                .font (.caption)
                .foregroundColor (.secondary)
                .fixedSize (horizontal: false, vertical: true)
        }
        .frame (maxWidth: .infinity, alignment: .leading)
        .padding (10)
        .background (Color (.secondarySystemBackground))
        .cornerRadius (8)
        .contextMenu {
            commandActions (for: example.code)
        }
    }
}

struct HelpView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            HelpView ()
        }
    }
}
