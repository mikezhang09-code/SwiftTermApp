//
//  ConfigurableTerminal.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 5/21/21.
//  Copyright © 2021 Miguel de Icaza. All rights reserved.
//

import SwiftUI

struct RunningTerminalConfig: View {
    @State var host: Host
    @Binding var showingModal: Bool
    @State var style: String = ""
    @State var fontName: String = ""
    @State var fontSize: CGFloat = 0

    func save () {
        host.style = style
        DataStore.shared.saveState()
        DataStore.shared.runtimeVisibleChanges.send(host)
        settings.fontName = fontName
        settings.fontSize = fontSize
    }
    
    var body: some View {
        NavigationView {
            
            Form {
                ThemeSelector(themeName: $style, showDefault: true) { t in
                    style = t
                }
                FontSelector (fontName: $fontName)
                FontSizeSelector (fontName: fontName, fontSize: $fontSize)
            }
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Cancel") {
                        self.showingModal = false
                    }
                }
                ToolbarItem (placement: .navigationBarTrailing) {
                    Button("Save") {
                        save ()
                        self.showingModal = false
                    }
                }
            }
        }
        .onAppear() {
            style = host.style
            fontSize = settings.fontSize
            fontName = settings.fontName
        }
    }
}

// For full screen Solution might be to use an external host UIViewController:
// https://gist.github.com/timothycosta/a43dfe25f1d8a37c71341a1ebaf82213
// https://stackoverflow.com/questions/56756318/swiftui-presentationbutton-with-modal-that-is-full-screen


struct ConfigurableUITerminal: View {
    @State var host: Host?
    @State var terminalView: SshTerminalView?
    @State var createNew: Bool = false
    @State var interactive: Bool = true
    @State var showConfig: Bool = false
    @State var showCommand: Bool = false
    @State var showClose: Bool = false
    @State var showFiles: Bool = false
    @State var showForwards: Bool = false
    @State var showAi: Bool = false
    @State var showAiCommand: Bool = false
    @State var showAiDiagnose: Bool = false

    func topMostViewController (_ t: UIViewController) -> UIViewController {
        if let presented = t.presentedViewController {
            return topMostViewController (presented)
        }
        
        if let navigation = t as? UINavigationController {
            return topMostViewController(navigation.visibleViewController ?? navigation)
        }
        
        if let tab = t as? UITabBarController {
            return topMostViewController (tab.selectedViewController ?? tab)
        }
        return t
    }

    func hideKeyboard () {
        if let visible = TerminalViewController.visibleTerminal {
            if visible.isFirstResponder {
                _ = visible.resignFirstResponder()
            } else {
                _ = visible.becomeFirstResponder()
            }
        }
    }
    
    func terminalGetter () -> AppTerminalView? {
        return TerminalViewController.visibleTerminal
    }
    
    var body: some View {
        SwiftUITerminal(host: host, existing: terminalView, createNew: createNew, interactive: interactive)
            .navigationTitle (Text ((terminalView?.host.alias ?? host?.alias) ?? "error"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarTrailing) {
                    ControlGroup {
                        Button (action: { self.showCommand = true }) {
                            Image(systemName: "note.text")
                        }
                        Button (action: { self.showFiles = true }) {
                            Image(systemName: "folder")
                        }
                        Button (action: { self.showForwards = true }) {
                            Image(systemName: "arrow.left.arrow.right")
                        }
                        Menu {
                            Button (action: { self.showAi = true }) {
                                Label (terminalGetter ()?.hasAiSelection == true ? "Explain Selection" : "Explain Output",
                                       systemImage: "text.magnifyingglass")
                            }
                            Button (action: { self.showAiDiagnose = true }) {
                                Label ("Diagnose Failure", systemImage: "stethoscope")
                            }
                            Button (action: { self.showAiCommand = true }) {
                                Label ("Get a Command", systemImage: "wand.and.stars")
                            }
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        Button (action: { self.showConfig = true }) {
                            Image(systemName: "gearshape")
                        }
                        Button (action: { self.hideKeyboard() }) {
                            Image(systemName: "keyboard")
                        }
                    }
                }
            }
            .sheet (isPresented: $showConfig, onDismiss: {
                // Give the keyboard back to the terminal, the sheet took it away
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                RunningTerminalConfig (host: terminalView?.host ?? host!, showingModal: $showConfig)
            }
            .sheet (isPresented: $showCommand) {
                NavigationView {
                    CommandPicker (terminalGetter: terminalGetter)
                }
            }
            .sheet (isPresented: $showFiles, onDismiss: {
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                SftpBrowserView (terminalGetter: terminalGetter)
            }
            .sheet (isPresented: $showForwards, onDismiss: {
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                PortForwardsView (host: terminalView?.host ?? host!, terminalGetter: terminalGetter)
            }
            .sheet (isPresented: $showAi, onDismiss: {
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                AiExplainView (terminalGetter: terminalGetter)
            }
            .sheet (isPresented: $showAiDiagnose, onDismiss: {
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                AiExplainView (terminalGetter: terminalGetter, mode: .diagnose)
            }
            .sheet (isPresented: $showAiCommand, onDismiss: {
                if let visible = TerminalViewController.visibleTerminal {
                    _ = visible.becomeFirstResponder()
                }
            }) {
                AiCommandView (terminalGetter: terminalGetter)
            }
    }
}

struct ConfigurableUITerminal_Previews: PreviewProvider {
    static var previews: some View {
        WrapperView ()
    }
    
    struct WrapperView: View {
        @State var host = DataController.preview.createSampleHost(0)
        @State var showingModal = false
        
        var body: some View {
            NavigationView {
                VStack {
                    ConfigurableUITerminal(host: host)
                    Text ("Below is the configuration")
                    RunningTerminalConfig(host: host, showingModal: $showingModal)
                }
            }
        }
    }
}
