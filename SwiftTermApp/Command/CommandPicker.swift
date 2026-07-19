//
//  CommandPicker.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 3/25/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import SwiftUI

struct CommandPicker: View {
    @EnvironmentObject var dataController: DataController
    private var snippets: FetchRequest<CUserSnippet>
    @Environment(\.managedObjectContext) var moc
    @Environment(\.dismiss) private var dismiss
    @State var terminalGetter: ()->AppTerminalView?
    @State private var searchText = ""

    init (terminalGetter: @escaping ()->AppTerminalView?) {
        snippets = FetchRequest<CUserSnippet>(entity: CUserSnippet.entity(), sortDescriptors: [
            NSSortDescriptor(keyPath: \CUserSnippet.sTitle, ascending: true)
        ])
        self._terminalGetter = State (initialValue: terminalGetter)
    }

    var body: some View {
        List {
            ForEach(searchResults, id: \.id) { snippet in
                // A Button so the whole row is tappable; a bare gesture only
                // covers the text, leaving most of the row dead.
                Button {
                    guard let terminal = terminalGetter () else {
                        return
                    }
                    dismiss()
                    terminal.send (txt: CommandPicker.forTerminal (snippet.command))
                } label: {
                    SnippetSummary(snippet: snippet)
                }
                .buttonStyle (.plain)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem (placement: .navigationBarLeading) {
                Button ("Dismiss") {
                    dismiss()
                }
            }
        }
    }
    
    /// A tty submits a line on carriage return, which is what the Return key
    /// sends; a bare newline is not treated as Enter, so a multi-line snippet
    /// sent verbatim runs together into one line ("ls" + "cd .." => "lscd ..").
    /// Translate line endings so each line of a snippet is entered as typed.
    static func forTerminal (_ command: String) -> String {
        command
            .replacingOccurrences (of: "\r\n", with: "\n")
            .replacingOccurrences (of: "\n", with: "\r")
    }

    var searchResults: [CUserSnippet] {
        if searchText.isEmpty {
            return snippets.wrappedValue.map { $0 }
        } else {
            return snippets.wrappedValue.filter { snippet in
                snippet.title.localizedCaseInsensitiveContains(searchText) || snippet.command.localizedCaseInsensitiveContains (searchText)
            }
        }
    }
}

struct CommandPicker_Previews: PreviewProvider {
    static var previews: some View {
        CommandPicker { return nil }
    }
}
