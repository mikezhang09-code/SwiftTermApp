//
//  SnippetSummary.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 3/25/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import SwiftUI

struct SnippetSummary: View {
    /// Must observe the managed object, not snapshot it: with `@State` the row
    /// never redraws when the snippet is edited, so your own edit only appears
    /// after relaunching the app.
    @ObservedObject var snippet: CUserSnippet
    var body: some View {
        VStack (alignment: .leading){
            Text (snippet.title)
                .bold()
            Text (snippet.command)
                .lineLimit(1)
                .foregroundColor(.secondary)
                .font (.system (.body, design: .monospaced))
        }
        // Fill the row and make the whole width hit-testable, otherwise only the
        // text itself responds to a tap and most of the row is dead space.
        .frame (maxWidth: .infinity, alignment: .leading)
        .contentShape (Rectangle ())
    }
}

struct SnippetSummary_Previews: PreviewProvider {
    static var previews: some View {
        SnippetSummary(snippet: DataController.preview.createSampleSnippet())
    }
}
