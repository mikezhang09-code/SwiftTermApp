//
//  AddKeyFromFile.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 5/4/20.
//  Copyright © 2020 Miguel de Icaza. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

///
/// A button that shows a file icon, and when selected, inserts the contents
/// of the file into the target field
///
struct ContentsFromFile: View {
    @Binding var target: String
    @State var pickerShown = false

    func setTarget (result: Result<URL, Error>)
    {
        guard case .success (let url) = result else {
            return
        }
        // fileImporter URLs are outside our sandbox, access must be bracketed
        let scoped = url.startAccessingSecurityScopedResource ()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource ()
            }
        }
        if let contents = try? String (contentsOf: url) {
            target = contents
        }
    }

    var body: some View {
        Image (systemName: "folder")
            .foregroundColor(ButtonColors.highColor)
            .font(Font.headline.weight(.light))
            .onTapGesture { self.pickerShown = true }
            .fileImporter(isPresented: $pickerShown, allowedContentTypes: [.item], onCompletion: setTarget)
            .help ("Pick a file")
    }
}

struct STFilePicker_Previews: PreviewProvider {
    static var previews: some View {
        ContentsFromFile (target: .constant (""))
    }
}
