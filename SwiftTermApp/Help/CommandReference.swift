//
//  CommandReference.swift
//  SwiftTermApp
//
//  The model behind the command reference shown under Help.  Two platforms are
//  covered: Unix (Linux and macOS) and PowerShell, which is what you get when
//  you SSH into a Windows host running OpenSSH.
//
//  The entries live in CommandsUnix.swift and CommandsPowerShell.swift.
//

import SwiftUI

enum CommandPlatform: String, CaseIterable, Identifiable {
    case unix
    case powershell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unix: return "Linux / macOS"
        case .powershell: return "PowerShell"
        }
    }
}

/// A worked example: a concrete invocation and what it actually does.
struct CommandExample: Identifiable {
    let id = UUID ()
    let code: String
    let explanation: String

    init (_ code: String, _ explanation: String) {
        self.code = code
        self.explanation = explanation
    }
}

struct CommandEntry: Identifiable {
    let id = UUID ()

    /// The canonical form shown in the list.
    let command: String
    /// One line, shown under the command in the list.
    let summary: String
    /// A paragraph or two explaining what the command does and when to reach
    /// for it.  Rendered as Markdown.
    let detail: String
    /// Concrete invocations worth knowing.
    let examples: [CommandExample]
    /// The mistake people actually make with this command, if there is one.
    let caution: String?

    init (command: String,
          summary: String,
          detail: String = "",
          examples: [CommandExample] = [],
          caution: String? = nil) {
        self.command = command
        self.summary = summary
        self.detail = detail
        self.examples = examples
        self.caution = caution
    }

    /// Search matches the explanation too, so looking for a concept ("permission",
    /// "disk full") finds the command even when the name gives nothing away.
    var searchText: String {
        ([command, summary, detail, caution ?? ""] + examples.flatMap { [$0.code, $0.explanation] })
            .joined (separator: " ")
    }

    var hasDetail: Bool { !detail.isEmpty || !examples.isEmpty }
}

struct CommandCategory: Identifiable {
    let id = UUID ()
    let name: String
    let icon: String
    /// Shown at the top of the category, to frame what the whole group is for.
    let intro: String
    let entries: [CommandEntry]

    init (name: String, icon: String, intro: String = "", entries: [CommandEntry]) {
        self.name = name
        self.icon = icon
        self.intro = intro
        self.entries = entries
    }
}

func commandGroups (for platform: CommandPlatform) -> [CommandCategory] {
    switch platform {
    case .unix: return unixCommandGroups
    case .powershell: return powershellCommandGroups
    }
}

/// Renders Markdown, falling back to the raw string so a malformed entry stays
/// readable rather than disappearing.
func helpMarkdown (_ source: String) -> AttributedString {
    (try? AttributedString (
        markdown: source,
        options: .init (interpretedSyntax: .inlineOnlyPreservingWhitespace)))
    ?? AttributedString (source)
}
