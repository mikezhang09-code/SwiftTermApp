//
//  SnippetBrowser.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 3/25/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import SwiftUI

struct SnippetBrowser: View {
    @EnvironmentObject var dataController: DataController
    private var snippets: FetchRequest<CUserSnippet>
    @Environment(\.managedObjectContext) var moc
    @State var activatedItem: CUserSnippet? = nil
    @State var newSnippet: Bool = false
    
    func delete (at offsets: IndexSet) {
        let snippetItems = snippets.wrappedValue
        for offset in offsets {
            dataController.delete(snippet: snippetItems [offset])
        }

        dataController.save()
    }
    
    init () {
        snippets = FetchRequest<CUserSnippet>(entity: CUserSnippet.entity(), sortDescriptors: [
            NSSortDescriptor(keyPath: \CUserSnippet.sTitle, ascending: true)
        ])
    }

    var body: some View {
        VStack {
            STButton (text: "Add Snippet", icon: "plus.circle") {
                self.newSnippet = true
            }
            if snippets.wrappedValue.count > 0 {
                List {
                    Section {
                        ForEach(snippets.wrappedValue, id: \.self) { snippet in
                            // A Button rather than onTapGesture: it makes the whole
                            // row tappable (a bare gesture only covers the text) and
                            // leaves the swipe available for onDelete, which the
                            // gesture was swallowing.
                            Button {
                                activatedItem = snippet
                            } label: {
                                SnippetSummary (snippet: snippet)
                            }
                            .buttonStyle (.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
                .listStyle(.grouped)
                .toolbar {
                    ToolbarItem (placement: .navigationBarTrailing) {
                        EditButton ()
                    }
                }
            } else {
                HStack (alignment: .top){
                    Image (systemName: "note.text")
                        .font (.title)
                    Text ("Snippets are groups of commands that you can paste in your terminal with the snippet icon.")
                        .font (.body)
                }.padding ()
                Spacer ()
            }
        }
        // Outside the branches, so the empty state gets a title too
        .navigationTitle (Text ("Snippets"))
        .sheet(isPresented: $newSnippet) {
            SnippetEditor (snippet: nil)
        }
        .sheet(item: $activatedItem) { item in
            SnippetEditor (snippet: item)
        }
    }
}

struct SnippetBrowser_Previews: PreviewProvider {
    static var previews: some View {
        SnippetBrowser()
    }
}
