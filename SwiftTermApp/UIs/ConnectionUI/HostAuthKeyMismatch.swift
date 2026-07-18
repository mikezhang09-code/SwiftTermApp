//
//  HostAuthKeyMismatch.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 6/21/21.
//  Copyright © 2021 Miguel de Icaza. All rights reserved.
//

import SwiftUI

struct HostAuthKeyMismatch: View {
    @State var alias: String
    @State var hostString: String
    @State var fingerprint: String
    var cancelCallback: () -> ()
    var acceptCallback: () -> ()

    var body: some View {
        // Header, scrollable explanation, and pinned buttons — same layout discipline as
        // HostAuthUnknown, so the actions stay reachable on a fixed-size iPad sheet.
        VStack (spacing: 0) {
            HStack (alignment: .top){
                Image (systemName: "exclamationmark.triangle")
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 30)
                    .padding (10)
                VStack (alignment: .leading){
                    Text ("Warning - Remote Host Identification Has Changed")
                        .font(.headline)
                        .padding([.bottom])
                    Text ("**Host:** \(alias)")
                        .font(.subheadline)
                }
                Spacer ()
            }
            .padding()
            .background(.yellow)

            ScrollView {
                Text ("**It is possible that someone is doing something nasty**.\n\nSomeone could be eavesdropping on you right now (man-in-the-middle attack).\n\nIt is also possible that the host key has just been changed, for example if the server was reinstalled. The fingerprint for the key sent by the remote host is:\n\n`\(fingerprint)`\n\nOnly accept the new key if you were expecting this change. Otherwise, go back.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding ()
            }

            Divider ()
            HStack (alignment: .center, spacing: 20) {
                Button ("Go Back", role: .cancel) { cancelCallback () }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Button ("Accept New Key", role: .destructive) { acceptCallback () }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Color.red)
            }
            .padding()
        }
    }
}

struct HostAuthKeyMismatch_Previews: PreviewProvider {
    static var previews: some View {
        HostAuthKeyMismatch(alias: "mac", hostString: "localhost:20", fingerprint: "ECDSA SHA256:AAAAB3NzaC1yc2EAAAADAQABAAABgQDCOFP4DoqHmagF", cancelCallback: {}, acceptCallback: {})
    }
}
