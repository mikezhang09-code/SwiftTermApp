//
//  InputKeyboard.swift
//  SwiftTermApp
//
//  On-screen keyboard support for the terminal:
//  - TerminalKeyboardBar: the accessory strip shown above the keyboard (esc/ctrl/tab,
//    common symbols, F-keys, arrows), plus a keyboard-mode button and a collapse button.
//  - FullKeyboardView: an app-drawn QWERTY keyboard, used when iPadOS suppresses the
//    system keyboard (hardware keyboard attached, Apple Pencil/Scribble active).
//  - FunctionPadView: a compact pad with F1-F10, brackets and navigation keys.
//
//  Created by Miguel de Icaza on 6/28/21.
//  Copyright © 2021 Miguel de Icaza. All rights reserved.
//

import UIKit
import SwiftTerm

/// Which software keyboard the terminal shows above the accessory bar.
enum SoftKeyboardMode: Int {
    /// The standard iOS keyboard: dictation, emoji and international input methods work,
    /// but iPadOS hides it when it believes a hardware keyboard is connected.
    case system = 0
    /// The app-drawn QWERTY keyboard: always available, even with a hardware keyboard attached.
    case qwerty = 1
    /// F1-F10, brackets and navigation keys.
    case functionPad = 2

    static let defaultsKey = "softKeyboardMode"

    static var saved: SoftKeyboardMode {
        SoftKeyboardMode (rawValue: UserDefaults.standard.integer (forKey: defaultsKey)) ?? .system
    }

    func save () {
        UserDefaults.standard.set (rawValue, forKey: SoftKeyboardMode.defaultsKey)
    }

    var next: SoftKeyboardMode {
        SoftKeyboardMode (rawValue: (rawValue + 1) % 3) ?? .system
    }

    /// SF Symbol shown on the mode button while this mode is active
    var icon: String {
        switch self {
        case .system: return "keyboard"
        case .qwerty: return "keyboard.fill"
        case .functionPad: return "function"
        }
    }
}

// MARK: - Shared key-button helpers

private let keyBackground = UIColor { tc in
    tc.userInterfaceStyle == .dark ? UIColor (white: 0.42, alpha: 1) : UIColor.white
}
private let specialKeyBackground = UIColor { tc in
    tc.userInterfaceStyle == .dark ? UIColor (white: 0.26, alpha: 1) : UIColor (white: 0.82, alpha: 1)
}

/// A key button whose selected state is shown by tinting the background (used for ctrl/touch toggles)
private class SelectableKeyButton: UIButton {
    var normalBackground: UIColor?

    override var isSelected: Bool {
        didSet {
            backgroundColor = isSelected ? tintColor : normalBackground
        }
    }
}

private func makeKey (_ title: String, icon: String? = nil, special: Bool = false, fontSize: CGFloat = 16,
                      onPress: @escaping () -> ()) -> SelectableKeyButton
{
    let b = SelectableKeyButton (type: .roundedRect)
    b.layer.cornerRadius = 5
    b.layer.masksToBounds = false
    b.layer.shadowOffset = CGSize (width: 0, height: 1.0)
    b.layer.shadowRadius = 0.0
    b.layer.shadowOpacity = 0.35
    b.normalBackground = special ? specialKeyBackground : keyBackground
    b.backgroundColor = b.normalBackground
    b.setTitleColor (.label, for: .normal)
    b.setTitleColor (.label, for: .selected)
    if let icon, let img = UIImage (systemName: icon, withConfiguration: UIImage.SymbolConfiguration (pointSize: 14.0)) {
        b.setImage (img.withTintColor (.label, renderingMode: .alwaysOriginal), for: .normal)
    } else {
        b.setTitle (title, for: .normal)
        b.titleLabel?.font = UIFont.systemFont (ofSize: fontSize)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.numberOfLines = 1
    }
    b.addAction (UIAction { _ in
        UIDevice.current.playInputClick ()
        onPress ()
    }, for: .touchDown)
    return b
}

/// Runs a key action once on press, then auto-repeats while the key stays pressed
private class AutoRepeater {
    private var timer: Timer?
    private var pendingStart: DispatchWorkItem?

    func attach (to button: UIButton, action: @escaping () -> ()) {
        button.addAction (UIAction { [weak self] _ in
            guard let self else { return }
            self.cancel ()
            let start = DispatchWorkItem {
                self.timer = Timer.scheduledTimer (withTimeInterval: 0.1, repeats: true) { _ in
                    action ()
                }
            }
            self.pendingStart = start
            DispatchQueue.main.asyncAfter (deadline: .now () + 0.6, execute: start)
        }, for: .touchDown)
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel] {
            button.addAction (UIAction { [weak self] _ in self?.cancel () }, for: event)
        }
    }

    func cancel () {
        pendingStart?.cancel ()
        pendingStart = nil
        timer?.invalidate ()
        timer = nil
    }
}

// MARK: - Accessory bar

///
/// The strip shown above the keyboard: esc/ctrl/tab, common symbols, as many F-keys as
/// fit, arrows, the touch-reporting toggle, the keyboard-mode button and a collapse button.
///
/// This is the app's replacement for SwiftTerm's TerminalAccessory (which is public but not
/// open, so it cannot be extended with the mode button).  The control-modifier composition
/// for typed text is handled by `AppTerminalView.insertText`.
///
class TerminalKeyboardBar: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?

    /// Set when the ctrl key is latched; consumed by `AppTerminalView.insertText`
    var controlOn: Bool = false {
        didSet {
            ctrlButton?.isSelected = controlOn
        }
    }

    private(set) var mode: SoftKeyboardMode = .system
    private var ctrlButton: SelectableKeyButton?
    private var touchButton: SelectableKeyButton?
    private var modeButton: UIButton?
    private var views: [UIView] = []
    private var repeaters: [AutoRepeater] = []
    private var lastLaidOutSize = CGSize.zero

    init (frame: CGRect, container: TerminalView) {
        self.terminalView = container
        super.init (frame: frame, inputViewStyle: .keyboard)
        allowsSelfSizing = true
    }

    required init? (coder: NSCoder) {
        fatalError ("init(coder:) has not been implemented")
    }

    public var enableInputClicksWhenVisible: Bool { true }

    override var bounds: CGRect {
        didSet {
            if bounds.size != lastLaidOutSize {
                lastLaidOutSize = bounds.size
                setupUI ()
            }
        }
    }

    /// Maps a typed character to its control-key byte sequence (ctrl-a -> 0x01 etc.)
    static func applyControl (to text: String) -> [UInt8] {
        var result: [UInt8] = []
        for scalar in text.unicodeScalars {
            if scalar == " " {
                result.append (0)
                continue
            }
            let upper = String (scalar).uppercased ().unicodeScalars
            if upper.count == 1, let u = upper.first, u.value >= 0x40, u.value < 0x80 {
                result.append (UInt8 (u.value & 0x1f))
            } else {
                result.append (contentsOf: Array (String (scalar).utf8))
            }
        }
        return result
    }

    func send (_ data: [UInt8]) {
        terminalView?.send (data)
    }

    private func sendArrow (app: [UInt8], normal: [UInt8]) {
        guard let tv = terminalView else { return }
        tv.send (tv.getTerminal ().applicationCursor ? app : normal)
    }

    /// Installs the given keyboard mode: swaps the terminal's inputView and persists the choice
    func apply (mode: SoftKeyboardMode) {
        guard let tv = terminalView else { return }
        self.mode = mode
        mode.save ()
        let width = tv.window?.bounds.width ?? UIScreen.main.bounds.width
        switch mode {
        case .system:
            tv.inputView = nil
        case .qwerty:
            tv.inputView = FullKeyboardView (frame: CGRect (x: 0, y: 0, width: width, height: FullKeyboardView.preferredHeight), terminalView: tv)
        case .functionPad:
            tv.inputView = FunctionPadView (frame: CGRect (x: 0, y: 0, width: width, height: FunctionPadView.preferredHeight), terminalView: tv)
        }
        updateModeIcon ()
        tv.reloadInputViews ()
    }

    private func updateModeIcon () {
        if let img = UIImage (systemName: mode.icon, withConfiguration: UIImage.SymbolConfiguration (pointSize: 14.0)) {
            modeButton?.setImage (img.withTintColor (.label, renderingMode: .alwaysOriginal), for: .normal)
        }
    }

    func setupUI ()
    {
        for view in views {
            view.removeFromSuperview ()
        }
        views = []
        repeaters = []
        guard terminalView != nil else { return }

        let small = frame.width < 380
        let minWidth: CGFloat = small ? 24 : (UIDevice.current.userInterfaceIdiom == .phone ? 26 : 34)
        let pad = 4.0
        let keyHeight = frame.height - 8

        func sized (_ b: UIButton, _ width: CGFloat? = nil) -> UIButton {
            b.sizeToFit ()
            let w = max (width ?? 0, max (b.frame.width, minWidth))
            b.frame = CGRect (x: 0, y: 4, width: w, height: keyHeight)
            return b
        }

        // Left side: esc, ctrl, tab
        var leftViews: [UIView] = []
        leftViews.append (sized (makeKey ("esc", icon: small ? "escape" : nil, special: true) { [weak self] in self?.send ([0x1b]) }))
        let ctrl = makeKey ("ctrl", icon: small ? "control" : nil, special: true) { [weak self] in
            self?.controlOn.toggle ()
        }
        ctrlButton = ctrl
        leftViews.append (sized (ctrl))
        leftViews.append (sized (makeKey ("", icon: "arrow.right.to.line.compact", special: true) { [weak self] in self?.send ([0x9]) }))

        // Right side: arrows, touch toggle, keyboard mode, collapse
        var rightViews: [UIView] = []
        func addArrow (_ icon: String, app: [UInt8], normal: [UInt8]) {
            let b = makeKey ("", icon: icon) { [weak self] in self?.sendArrow (app: app, normal: normal) }
            let repeater = AutoRepeater ()
            repeater.attach (to: b) { [weak self] in self?.sendArrow (app: app, normal: normal) }
            repeaters.append (repeater)
            rightViews.append (sized (b))
        }
        addArrow ("arrow.left", app: EscapeSequences.moveLeftApp, normal: EscapeSequences.moveLeftNormal)
        addArrow ("arrow.up", app: EscapeSequences.moveUpApp, normal: EscapeSequences.moveUpNormal)
        addArrow ("arrow.down", app: EscapeSequences.moveDownApp, normal: EscapeSequences.moveDownNormal)
        addArrow ("arrow.right", app: EscapeSequences.moveRightApp, normal: EscapeSequences.moveRightNormal)

        let touch = makeKey ("", icon: "hand.draw", special: true) { [weak self] in
            guard let tv = self?.terminalView else { return }
            tv.allowMouseReporting.toggle ()
            self?.touchButton?.isSelected = tv.allowMouseReporting
        }
        touch.isSelected = terminalView?.allowMouseReporting ?? false
        touchButton = touch
        rightViews.append (sized (touch))

        let modeB = makeKey ("", icon: mode.icon, special: true) { [weak self] in
            guard let self else { return }
            self.apply (mode: self.mode.next)
        }
        modeButton = modeB
        rightViews.append (sized (modeB))

        rightViews.append (sized (makeKey ("", icon: "keyboard.chevron.compact.down", special: true) { [weak self] in
            _ = self?.terminalView?.resignFirstResponder ()
        }))

        // Middle: common symbols, the tmux prefix and as many F-keys as fit
        let fixedUsed = (leftViews + rightViews).reduce (2.0 + 2.0) { $0 + $1.frame.width + pad }
        var available = frame.width - fixedUsed
        var floatViews: [UIView] = []
        func addFloat (_ title: String, special: Bool = false, onPress: @escaping () -> ()) {
            let b = sized (makeKey (title, special: special, fontSize: small ? 12 : 16, onPress: onPress))
            if available - (b.frame.width + pad) < 0 {
                return
            }
            available -= b.frame.width + pad
            floatViews.append (b)
        }
        for symbol in ["~", "|", "/", "-"] {
            addFloat (symbol) { [weak self] in self?.terminalView?.insertText (symbol) }
        }
        // The tmux prefix: sends ctrl-b directly, so "detach" is just this key followed by "d"
        addFloat ("⌃b", special: true) { [weak self] in self?.send ([0x02]) }
        for fkey in 0..<10 {
            addFloat ("F\(fkey + 1)") { [weak self] in self?.send (EscapeSequences.cmdF [fkey]) }
        }

        // Layout: left + middle flow from the left edge, right side is right-aligned
        var x = 2.0
        for view in leftViews + floatViews {
            view.frame.origin.x = x
            x += view.frame.width + pad
        }
        var right = frame.width - 2
        for view in rightViews.reversed () {
            view.frame.origin.x = right - view.frame.width
            right -= view.frame.width + pad
        }

        views = leftViews + floatViews + rightViews
        for view in views {
            addSubview (view)
        }
    }
}

// MARK: - Function pad

///
/// The compact alternate keyboard: F1-F10, brackets/operators and navigation keys.
///
class FunctionPadView: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?
    private var views: [UIView] = []
    private var lastLaidOutSize = CGSize.zero

    static var preferredHeight: CGFloat {
        max (UIScreen.main.bounds.height / 5, 150)
    }

    init (frame: CGRect, terminalView: TerminalView?) {
        self.terminalView = terminalView
        super.init (frame: frame, inputViewStyle: .keyboard)
        buildUI ()
    }

    required init? (coder: NSCoder) {
        fatalError ("init(coder:) has not been implemented")
    }

    public var enableInputClicksWhenVisible: Bool { true }

    override var bounds: CGRect {
        didSet {
            if bounds.size != lastLaidOutSize {
                lastLaidOutSize = bounds.size
                buildUI ()
            }
        }
    }

    private struct PadKey {
        var label: String
        var icon: String? = nil
        var special: Bool = false
        var action: (TerminalView) -> ()
    }

    private func charKey (_ ch: String) -> PadKey {
        PadKey (label: ch) { tv in tv.insertText (ch) }
    }

    private func rows () -> [[PadKey]] {
        var fkeys: [PadKey] = []
        for fkey in 0..<10 {
            fkeys.append (PadKey (label: "F\(fkey + 1)") { tv in tv.send (EscapeSequences.cmdF [fkey]) })
        }
        let row2: [PadKey] = ["[", "]", "{", "}", "<", ">", "&"].map (charKey) + [
            PadKey (label: "ins", special: true) { tv in tv.send (EscapeSequences.cmdInsert) },
            PadKey (label: "home", special: true) { tv in
                tv.send (tv.getTerminal ().applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal)
            },
            PadKey (label: "pgup", special: true) { tv in tv.send (EscapeSequences.cmdPageUp) },
        ]
        let row3: [PadKey] = ["+", "-", "*", "=", "%", "`", "\\"].map (charKey) + [
            PadKey (label: "del", icon: "delete.forward", special: true) { tv in tv.send (EscapeSequences.cmdDelKey) },
            PadKey (label: "end", special: true) { tv in
                tv.send (tv.getTerminal ().applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal)
            },
            PadKey (label: "pgdn", special: true) { tv in tv.send (EscapeSequences.cmdPageDown) },
        ]
        return [fkeys, row2, row3]
    }

    private func buildUI () {
        for view in views {
            view.removeFromSuperview ()
        }
        views = []

        let source = rows ()
        let bottomPad = 16.0
        let slotWidth = frame.width / 10
        let slotHeight = (frame.height - bottomPad) / Double (source.count)
        let xpadding = min (slotWidth * 0.1, 4.0)
        let ypadding = min (slotHeight * 0.1, 4.0)

        var y = ypadding
        for row in source {
            var x = xpadding
            for key in row {
                let b = makeKey (key.label, icon: key.icon, special: key.special, fontSize: 16) { [weak self] in
                    guard let tv = self?.terminalView else { return }
                    key.action (tv)
                }
                b.frame = CGRect (x: x, y: y, width: slotWidth - xpadding * 2, height: slotHeight - ypadding * 2)
                x += slotWidth
                views.append (b)
                addSubview (b)
            }
            y += slotHeight
        }
    }
}

// MARK: - App-drawn QWERTY keyboard

///
/// A QWERTY keyboard drawn by the app.  Unlike the system keyboard, iPadOS shows custom
/// input views even when it believes a hardware keyboard is connected, so this keyboard
/// is always available.
///
class FullKeyboardView: UIInputView, UIInputViewAudioFeedback {
    weak var terminalView: TerminalView?

    enum Plane {
        case letters, numbers, symbols
    }

    private enum QKey {
        case char (String)
        case shift
        case backspace
        case plane (Plane, String)
        case space
        case ret
    }

    private var plane: Plane = .letters
    private var shifted = false
    private var views: [UIView] = []
    private var letterButtons: [(UIButton, String)] = []
    private var shiftButton: UIButton?
    private var repeater = AutoRepeater ()
    private var lastLaidOutSize = CGSize.zero

    static var preferredHeight: CGFloat {
        UIDevice.current.userInterfaceIdiom == .phone ? 230 : 300
    }

    init (frame: CGRect, terminalView: TerminalView?) {
        self.terminalView = terminalView
        super.init (frame: frame, inputViewStyle: .keyboard)
        buildUI ()
    }

    required init? (coder: NSCoder) {
        fatalError ("init(coder:) has not been implemented")
    }

    public var enableInputClicksWhenVisible: Bool { true }

    override var bounds: CGRect {
        didSet {
            if bounds.size != lastLaidOutSize {
                lastLaidOutSize = bounds.size
                buildUI ()
            }
        }
    }

    // Rows with widths in tenths of the keyboard width; `space` absorbs the remainder
    private func rows () -> [[(QKey, CGFloat)]] {
        let bottomRow: [(QKey, CGFloat)] = [
            (.plane (plane == .letters ? .numbers : .letters, plane == .letters ? "123" : "ABC"), 1.4),
            (.char (","), 1),
            (.space, 0),
            (.char ("."), 1),
            (.ret, 1.8),
        ]
        switch plane {
        case .letters:
            return [
                "qwertyuiop".map { (QKey.char (String ($0)), CGFloat (1)) },
                "asdfghjkl".map { (QKey.char (String ($0)), CGFloat (1)) },
                [(.shift, 1.4)] + "zxcvbnm".map { (QKey.char (String ($0)), CGFloat (1)) } + [(.backspace, 1.4)],
                bottomRow,
            ]
        case .numbers:
            return [
                "1234567890".map { (QKey.char (String ($0)), CGFloat (1)) },
                ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { (QKey.char ($0), CGFloat (1)) },
                [(.plane (.symbols, "#+="), 1.4)] + ["_", "?", "!", "'", "*", "#", "%"].map { (QKey.char ($0), CGFloat (1)) } + [(.backspace, 1.4)],
                bottomRow,
            ]
        case .symbols:
            return [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { (QKey.char ($0), CGFloat (1)) },
                ["_", "\\", "|", "~", "<", ">", "`", "$", "\"", "'"].map { (QKey.char ($0), CGFloat (1)) },
                [(.plane (.numbers, "123"), 1.4)] + [";", ":", "&", "?", "!", "@", "•"].map { (QKey.char ($0), CGFloat (1)) } + [(.backspace, 1.4)],
                bottomRow,
            ]
        }
    }

    private func tapChar (_ ch: String) {
        guard let tv = terminalView else { return }
        let effective = (plane == .letters && shifted) ? ch.uppercased () : ch
        // Apply the ctrl latch here rather than relying on the insertText pipeline,
        // so ctrl+letter works regardless of how iOS routes text input
        if let bar = tv.inputAccessoryView as? TerminalKeyboardBar, bar.controlOn {
            bar.controlOn = false
            tv.send (TerminalKeyboardBar.applyControl (to: effective))
        } else {
            tv.insertText (effective)
        }
        if shifted {
            shifted = false
            updateShiftState ()
        }
    }

    private func updateShiftState () {
        for (button, ch) in letterButtons {
            button.setTitle (shifted ? ch.uppercased () : ch, for: .normal)
        }
        if let shiftButton,
           let img = UIImage (systemName: shifted ? "shift.fill" : "shift",
                              withConfiguration: UIImage.SymbolConfiguration (pointSize: 14.0)) {
            shiftButton.setImage (img.withTintColor (.label, renderingMode: .alwaysOriginal), for: .normal)
        }
    }

    private func buildUI () {
        for view in views {
            view.removeFromSuperview ()
        }
        views = []
        letterButtons = []
        shiftButton = nil
        repeater.cancel ()

        let source = rows ()
        let bottomPad = 16.0
        let unit = frame.width / 10
        let rowHeight = (frame.height - bottomPad) / Double (source.count)
        let xpadding = min (unit * 0.06, 3.0)
        let ypadding = min (rowHeight * 0.08, 5.0)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone

        var y = ypadding
        for row in source {
            let fixedUnits = row.reduce (0.0) { $0 + $1.1 }
            let hasSpace = row.contains { if case .space = $0.0 { return true } else { return false } }
            let spaceUnits = hasSpace ? max (10 - fixedUnits, 1) : 0
            let rowUnits = fixedUnits + spaceUnits
            var x = (10 - rowUnits) / 2 * unit

            for (key, units) in row {
                let width = (hasSpace && { if case .space = key { return true } else { return false } } ()) ? spaceUnits * unit : units * unit
                let b: UIButton
                switch key {
                case .char (let ch):
                    b = makeKey (plane == .letters && shifted ? ch.uppercased () : ch,
                                 fontSize: isPhone ? 20 : 22) { [weak self] in self?.tapChar (ch) }
                    if plane == .letters && "abcdefghijklmnopqrstuvwxyz".contains (ch) {
                        letterButtons.append ((b, ch))
                    }
                case .shift:
                    b = makeKey ("", icon: shifted ? "shift.fill" : "shift", special: true) { [weak self] in
                        guard let self else { return }
                        self.shifted.toggle ()
                        self.updateShiftState ()
                    }
                    shiftButton = b
                case .backspace:
                    b = makeKey ("", icon: "delete.left", special: true) { [weak self] in
                        self?.terminalView?.deleteBackward ()
                    }
                    repeater.attach (to: b) { [weak self] in self?.terminalView?.deleteBackward () }
                case .plane (let target, let label):
                    b = makeKey (label, special: true, fontSize: 15) { [weak self] in
                        guard let self else { return }
                        self.plane = target
                        self.shifted = false
                        self.buildUI ()
                    }
                case .space:
                    b = makeKey ("space", fontSize: 15) { [weak self] in
                        self?.terminalView?.insertText (" ")
                    }
                case .ret:
                    b = makeKey ("", icon: "return", special: true) { [weak self] in
                        self?.terminalView?.insertText ("\n")
                    }
                }
                b.frame = CGRect (x: x + xpadding, y: y, width: width - xpadding * 2, height: rowHeight - ypadding * 2)
                x += width
                views.append (b)
                addSubview (b)
            }
            y += rowHeight
        }
    }
}
