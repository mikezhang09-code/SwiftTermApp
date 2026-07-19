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
                    VStack (alignment: .leading, spacing: 8) {
                        Text (section.heading)
                            .font (.headline)
                        // The bodies are authored as Markdown; falling back to the
                        // raw string keeps a malformed entry readable rather than blank.
                        Text ((try? AttributedString (
                            markdown: section.body,
                            options: .init (interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                              ?? AttributedString (section.body))
                            .font (.body)
                            .fixedSize (horizontal: false, vertical: true)
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
            return matches.isEmpty ? nil : CommandCategory (name: group.name, icon: group.icon, entries: matches)
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
                        Section (header: Label (group.name, systemImage: group.icon)) {
                            ForEach (group.entries) { entry in
                                CommandRow (entry: entry)
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

struct CommandRow: View {
    let entry: CommandEntry
    @State private var copied = false

    /// A terminal is only offered as an insert target when one is on screen;
    /// reaching Help from the home screen usually means there is none.
    private var activeTerminal: AppTerminalView? {
        TerminalViewController.visibleTerminal
    }

    var body: some View {
        VStack (alignment: .leading, spacing: 3) {
            HStack {
                Text (entry.command)
                    .font (.system (.body, design: .monospaced))
                    .textSelection (.enabled)
                Spacer ()
                if copied {
                    Image (systemName: "checkmark")
                        .foregroundColor (.secondary)
                        .font (.caption)
                }
            }
            Text (entry.summary)
                .font (.caption)
                .foregroundColor (.secondary)
                .fixedSize (horizontal: false, vertical: true)
        }
        .contentShape (Rectangle ())
        .onTapGesture { copy () }
        .contextMenu {
            Button {
                copy ()
            } label: {
                Label ("Copy", systemImage: "doc.on.doc")
            }
            if let terminal = activeTerminal {
                Button {
                    // Deliberately no trailing newline: the command is typed into
                    // the prompt so it can be read and edited before it runs.
                    terminal.send (Array (entry.command.utf8))
                } label: {
                    Label ("Insert into Terminal", systemImage: "terminal")
                }
            }
        }
    }

    func copy () {
        UIPasteboard.general.string = entry.command
        copied = true
        DispatchQueue.main.asyncAfter (deadline: .now () + 1.2) {
            copied = false
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
