//
//  UserGuide.swift
//  SwiftTermApp
//
//  The user-facing guide shown under Help.  The content is stored as data so
//  the topic list and the detail pages stay in sync, and so topics can be
//  searched without having to walk a view hierarchy.
//

import SwiftUI

/// The kinds of content a guide section can hold.
///
/// Text carrying a `{symbolname}` token renders the live SF Symbol inline, so
/// the icon shown in the guide is the same one drawn in the toolbar and can
/// never drift out of date the way a screenshot would.
enum GuideBlock: Identifiable {
    /// A paragraph, rendered as Markdown.
    case prose (String)
    /// Numbered steps, to be followed in order.
    case steps ([String])
    /// An unordered list, for things that are not a sequence.
    case bullets ([String])
    /// A terminal transcript.  Lines starting with "$ " are shown as input.
    case terminal ([String])
    /// A short aside worth noticing.
    case tip (String)

    var id: String {
        switch self {
        case .prose (let s): return "p" + s
        case .steps (let s): return "s" + s.joined ()
        case .bullets (let s): return "b" + s.joined ()
        case .terminal (let s): return "t" + s.joined ()
        case .tip (let s): return "n" + s
        }
    }

    var searchText: String {
        switch self {
        case .prose (let s), .tip (let s): return s
        case .steps (let s), .bullets (let s), .terminal (let s):
            return s.joined (separator: " ")
        }
    }
}

/// A single block inside a guide topic.  Bodies are rendered as Markdown, so
/// they can use **bold**, `code` and bullet lists.
struct GuideSection: Identifiable {
    let id = UUID ()
    let heading: String
    let blocks: [GuideBlock]

    init (heading: String, blocks: [GuideBlock]) {
        self.heading = heading
        self.blocks = blocks
    }

    /// Prose-only section, which is what most topics still are.
    init (heading: String, body: String) {
        self.init (heading: heading, blocks: [.prose (body)])
    }

    var body: String { blocks.map { $0.searchText }.joined (separator: " ") }
}

struct GuideTopic: Identifiable {
    let id = UUID ()
    let title: String
    let icon: String
    let summary: String
    let sections: [GuideSection]

    /// The text used when matching a topic against the search field.
    var searchText: String {
        ([title, summary] + sections.flatMap { [$0.heading, $0.body] }).joined (separator: " ")
    }
}

let userGuideTopics: [GuideTopic] = [
    GuideTopic (
        title: "Getting Started",
        icon: "flag",
        summary: "Make your first connection",
        sections: [
            GuideSection (
                heading: "What you will need",
                blocks: [
                    .prose ("""
                    Three things about the machine you want to reach: its **address** (a hostname like \
                    `server.example.com` or an IP like `192.168.1.10`), a **username** on it, and a way \
                    to prove who you are — either a password or an SSH key.

                    If you do not have a server yet, skip to the last step and try the Local Terminal \
                    instead.
                    """),
                ]),

            GuideSection (
                heading: "Step 1 — Add the host",
                blocks: [
                    .steps ([
                        "On the home screen, tap {desktopcomputer} **Hosts**.",
                        "Tap **+** in the top right.",
                        "Fill in **Alias** — the name you will see in your list. Something like *work laptop* or *prod web*.",
                        "Fill in **Host** — the address of the machine, such as `192.168.1.100`.",
                        "Fill in **Username** — who you log in as.",
                    ]),
                    .tip ("""
                    The alias is purely for you. Pick what you will recognise in six months, not the \
                    hostname you already forgot.

                    Connecting on a port other than 22? It is not with these fields — scroll down to \
                    **Other Options**, where **Port** sits alongside **Environment Variables**. \
                    Leaving it blank means 22.
                    """),
                ]),

            GuideSection (
                heading: "Step 2 — Choose how you log in",
                blocks: [
                    .prose ("""
                    Still in the same form, the **Authentication** row is a two-way switch between \
                    **Password** and **SSH Key**. What appears underneath changes with your choice:
                    """),
                    .bullets ([
                        "**Password** — a **Password** field appears. The {eye} button reveals what you typed, in case a long password went in wrong.",
                        "**SSH Key** — a key picker appears, listing the keys from {key} **Keys**.",
                    ]),
                    .prose ("""
                    Keys are strongly preferred. They live in the iOS keychain, they cannot be \
                    shoulder-surfed or guessed, and a lot of servers refuse password logins outright. \
                    The **SSH Keys and Known Hosts** topic walks through making one.
                    """),
                    .prose ("Tap **Save** when the form is complete."),
                ]),

            GuideSection (
                heading: "Step 3 — Connect",
                blocks: [
                    .steps ([
                        "Tap your new host in the list.",
                        "The first time, the app shows the server's **fingerprint** and asks whether to trust it. Accept it if it matches what you expect.",
                        "Enter your password or key passphrase if prompted.",
                    ]),
                    .prose ("You should land at a shell prompt that looks something like this:"),
                    .terminal ([
                        "Last login: Mon Jul 19 09:14:02 2026 from 10.0.0.4",
                        "$ whoami",
                        "mike",
                        "$ ",
                    ]),
                    .tip ("""
                    That fingerprint prompt is the one moment protecting you from an impostor server. \
                    If you can, check it against a fingerprint you obtained some other way. Once \
                    accepted it is remembered under **Known Hosts** and you will not be asked again.
                    """),
                ]),

            GuideSection (
                heading: "Step 4 — Find your way around",
                blocks: [
                    .prose ("Once connected, the toolbar at the top right gives you:"),
                    .bullets ([
                        "{note.text} **Snippets** — paste commands you have saved.",
                        "{folder} **Files** — an SFTP browser on this same connection.",
                        "{arrow.left.arrow.right} **Port forwarding** — tunnel a port over this connection.",
                        "{sparkles} **AI** — explain output, diagnose a failure, or get a command.",
                        "{gearshape} **Appearance** — theme and font for this session.",
                        "{keyboard} **Keyboard** — show or hide the on-screen keyboard.",
                    ]),
                ]),

            GuideSection (
                heading: "No server? Try the Local Terminal",
                blocks: [
                    .prose ("""
                    {ipad.landscape} **Local Terminal** on the home screen gives you a real shell \
                    running inside the app, with no server and no setup at all.
                    """),
                    .terminal ([
                        "$ ls",
                        "Documents    Downloads",
                        "$ echo hello",
                        "hello",
                        "$ ",
                    ]),
                    .prose ("""
                    It is the best place to get comfortable with the keyboard, snippets and the AI \
                    features before you point them at a machine that matters.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Hosts and Connections",
        icon: "desktopcomputer",
        summary: "Managing servers and running sessions",
        sections: [
            GuideSection (
                heading: "Several terminals at once",
                body: """
                Connecting to a host opens a terminal but does not close the others.  **Terminals** on \
                the home screen lists everything currently running, with a live count next to it, and \
                lets you jump back to any session or close it.
                """),
            GuideSection (
                heading: "Per-host appearance",
                body: """
                Each host can override the global colour theme.  Edit the host and use the \
                **Appearance** section; leave it on *Default* to follow the theme you picked in \
                Settings.
                """),
            GuideSection (
                heading: "Environment variables and startup",
                body: """
                A host can carry environment variables that are sent when the session opens.  Use these \
                for things like `TERM`, `LANG`, or a variable your login scripts expect.
                """),
            GuideSection (
                heading: "Surviving disconnects",
                body: """
                Mobile connections drop.  If you set a host's reconnect type to **tmux**, the app will \
                attach to a tmux session on the server, so your work survives a dropped link and \
                resumes where it left off.

                Without tmux, a dropped connection ends the shell and anything running in it.
                """),
            GuideSection (
                heading: "History",
                body: """
                **History** records your past connections, so you can see when you last reached a given \
                machine.
                """),
        ]),

    GuideTopic (
        title: "SSH Keys and Known Hosts",
        icon: "key",
        summary: "Creating, importing and trusting keys",
        sections: [
            GuideSection (
                heading: "Creating a key",
                body: """
                Go to **Keys** and add a new one.  Ed25519 is the good default: it is short, fast and \
                secure.  RSA is available for older servers that have not been updated.

                You may protect the key with a passphrase.  The private key never leaves the device's \
                keychain.
                """),
            GuideSection (
                heading: "Getting the key onto the server",
                body: """
                Copy the **public** key from the key's detail page and append it to \
                `~/.ssh/authorized_keys` on the server.  From an existing session you can run:

                    mkdir -p ~/.ssh && chmod 700 ~/.ssh
                    echo 'PASTE-PUBLIC-KEY-HERE' >> ~/.ssh/authorized_keys
                    chmod 600 ~/.ssh/authorized_keys

                Never paste the *private* key anywhere.
                """),
            GuideSection (
                heading: "Importing an existing key",
                body: """
                You can import a key you already use elsewhere by pasting its contents or opening it \
                from the Files app.  Encrypted private keys will ask for their passphrase.
                """),
            GuideSection (
                heading: "Known Hosts",
                body: """
                **Known Hosts** lists the server fingerprints you have accepted.  If a server's key \
                changes you will get a warning on the next connection.  That usually means the server \
                was rebuilt — but it can also mean someone is impersonating it, so verify before you \
                delete the old entry and accept the new one.
                """),
        ]),

    GuideTopic (
        title: "The Keyboard",
        icon: "keyboard",
        summary: "Three input modes, modifiers and function keys",
        sections: [
            GuideSection (
                heading: "The bar above the keyboard",
                blocks: [
                    .prose ("""
                    A terminal needs keys a phone keyboard does not have, so the app adds its own bar \
                    just above the keyboard.  It carries:
                    """),
                    .bullets ([
                        "**esc** {escape} — the Escape key, which vi and many full-screen programs lean on.",
                        "**ctrl** {control} — the Control modifier.  See below.",
                        "{arrow.right.to.line.compact} — Tab, for completing file names.",
                        "{arrow.left} {arrow.up} {arrow.down} {arrow.right} — arrows, for moving the cursor and walking back through history.",
                        "{hand.draw} — switches dragging between moving the cursor and selecting text.",
                        "{keyboard.chevron.compact.down} — hides the keyboard to give the terminal the whole screen.",
                    ]),
                ]),

            GuideSection (
                heading: "Three keyboard modes",
                blocks: [
                    .prose ("""
                    One button on that bar cycles between three input modes.  Its icon tells you which \
                    one you are in, and the choice is remembered between launches.
                    """),
                    .bullets ([
                        "{keyboard} **System** — the normal iOS keyboard.  The right choice almost always.",
                        "{keyboard.fill} **App QWERTY** — the app's own keyboard, for when the system one refuses to appear.",
                        "{function} **Function pad** — a compact grid of function keys for programs that want them.",
                    ]),
                    .tip ("""
                    If the keyboard disappears and will not come back while you are using an Apple \
                    Pencil, that is exactly the problem App QWERTY exists to route around.  Tap the \
                    mode button until you reach {keyboard.fill}.
                    """),
                ]),

            GuideSection (
                heading: "Sending Control keys",
                blocks: [
                    .prose ("""
                    Control combinations talk to the running program rather than the shell.  Tap \
                    **ctrl**, then the letter — the modifier applies to exactly one following key and \
                    then switches itself off.
                    """),
                    .prose ("Pressing **ctrl** then `c` to stop a log you are following looks like this:"),
                    .terminal ([
                        "$ tail -f /var/log/syslog",
                        "Jul 19 09:14:02 web nginx: started",
                        "^C",
                        "$ ",
                    ]),
                    .prose ("The four worth committing to memory:"),
                    .bullets ([
                        "**ctrl** then `c` — interrupt what is running.  The way out of a stuck command.",
                        "**ctrl** then `d` — end of input; at an empty prompt it logs you out.",
                        "**ctrl** then `r` — search backwards through your command history.",
                        "**ctrl** then `z` — suspend the program; type `fg` to bring it back.",
                    ]),
                    .tip ("""
                    No Shift is involved: the key really is the lowercase letter.  That is why the bar \
                    labels the tmux prefix `⌃b` and not `⌃B`.
                    """),
                ]),

            GuideSection (
                heading: "Hardware keyboards",
                blocks: [
                    .prose ("""
                    With an external keyboard attached, modifiers work as you would expect and the \
                    on-screen bar collapses out of the way.  The {keyboard} button in the terminal's \
                    toolbar shows or hides the on-screen keyboard at any time.
                    """),
                ]),

            GuideSection (
                heading: "Making the text bigger",
                blocks: [
                    .prose ("""
                    Pinch to zoom inside the terminal to change the font size for that session alone.  \
                    The global default lives in {gear} **Settings**, where leaving the size on the \
                    system default lets it follow Dynamic Type.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Files and Transfers",
        icon: "folder",
        summary: "Browsing and moving files over SFTP",
        sections: [
            GuideSection (
                heading: "Opening the file browser",
                blocks: [
                    .prose ("""
                    The {folder} button in a connected terminal's toolbar opens a file browser running \
                    over the *same* SSH connection — no second login, no extra password, nothing to \
                    configure.
                    """),
                    .prose ("Along the top of the browser:"),
                    .bullets ([
                        "{arrow.turn.left.up} **..** — go up one directory.",
                        "{folder.badge.plus} — create a new directory here.",
                        "{square.and.arrow.up.on.square} — upload a file from your device.",
                        "{arrow.clockwise} — reload, if something changed on the server.",
                        "**Done** — close the browser and return to the terminal.",
                    ]),
                ]),

            GuideSection (
                heading: "Working with a file",
                blocks: [
                    .steps ([
                        "Tap a {folder.fill} folder to go into it.",
                        "Tap a {doc} file to download it, then save or share it wherever you like.",
                        "Swipe a row left and tap {trash} **Delete** to remove it from the server.",
                    ]),
                    .tip ("""
                    Deleting here deletes on the *server*.  There is no trash to recover it from, so \
                    check which host you are connected to first.
                    """),
                ]),

            GuideSection (
                heading: "Private keys get special treatment",
                blocks: [
                    .prose ("""
                    Tap a file that looks like a private key — shown with a {key} icon — and the app \
                    offers to **Import as SSH Key** rather than just downloading it.  That puts it \
                    straight into {key} **Keys**, where it can be attached to a host.
                    """),
                    .prose ("""
                    It is a quick way to adopt a key that already exists on a server you can reach, \
                    without copying it through anything less trustworthy.
                    """),
                ]),

            GuideSection (
                heading: "If the browser will not open",
                blocks: [
                    .prose ("""
                    SFTP is a *subsystem* of the SSH server, and it can be switched off independently \
                    of shell access.  If the browser reports it cannot start, check that the server's \
                    `sshd_config` has this line:
                    """),
                    .terminal ([
                        "$ grep -i sftp /etc/ssh/sshd_config",
                        "Subsystem sftp /usr/lib/openssh/sftp-server",
                    ]),
                    .prose ("""
                    If it is missing or commented out, the shell still works but no SFTP client will \
                    connect.  You can always fall back to `scp` and `rsync` from inside the terminal — \
                    both are in the **Command Reference**.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Snippets",
        icon: "note.text",
        summary: "Save and replay commands you type often",
        sections: [
            GuideSection (
                heading: "What they are",
                body: """
                A snippet is a saved block of one or more commands.  Instead of retyping a long \
                invocation on a phone keyboard, save it once and paste it whenever you need it.

                To run several commands in sequence, put each on its own line in the Command box — \
                pressing return there inserts a newline rather than saving.  A snippet of `ls` \
                followed by `cd ..` runs both, in order, exactly as if you had typed them.
                """),
            GuideSection (
                heading: "Using them",
                body: """
                The **note** button in a terminal's toolbar opens the snippet picker; choosing a \
                snippet types it into the current session.  It is available in SSH sessions and in \
                the Local Terminal.  Manage the list from **Snippets** on the home screen, where you \
                can add, edit and swipe to delete.
                """),
            GuideSection (
                heading: "A caution",
                body: """
                Snippets are pasted exactly as saved.  A snippet ending in a newline runs the moment \
                you pick it; one without a newline lands at the prompt so you can read and edit it \
                first.  Leaving the newline off is the safer habit, and essential for anything \
                destructive.
                """),
        ]),

    GuideTopic (
        title: "Port Forwarding",
        icon: "arrow.left.arrow.right",
        summary: "Tunnelling ports over your SSH connection",
        sections: [
            GuideSection (
                heading: "Local forwarding",
                body: """
                A local forward makes a port on the server reachable from this device.  The classic use \
                is reaching a database or an admin web page that only listens on the server's loopback \
                address: forward local `8080` to `127.0.0.1:80` on the server and open \
                `http://localhost:8080` on the iPad.
                """),
            GuideSection (
                heading: "Remote forwarding",
                body: """
                A remote forward is the mirror image: it exposes a port from this device on the server. \
                This is less common from a mobile client but useful for letting a server reach back to \
                something you are running locally.
                """),
            GuideSection (
                heading: "SOCKS proxy",
                body: """
                A dynamic forward turns the connection into a SOCKS proxy, letting the built-in browser \
                reach anything the server can reach.  It is the quickest way to view an internal site \
                without a full VPN.
                """),
            GuideSection (
                heading: "Managing forwards",
                body: """
                The **arrows** button in the terminal toolbar lists the forwards for that session and \
                lets you add or remove them while connected.  Forwards live as long as the session does.
                """),
        ]),

    GuideTopic (
        title: "AI Assistance",
        icon: "sparkles",
        summary: "Explain, Diagnose and command suggestions",
        sections: [
            GuideSection (
                heading: "Setting it up",
                body: """
                Open **AI** on the home screen, add a provider and paste your API key, then make it the \
                active provider.  The key is stored on the device.  Nothing is sent anywhere until you \
                explicitly invoke one of the three actions below.
                """),
            GuideSection (
                heading: "Explain",
                body: """
                The **sparkles** menu in a terminal offers *Explain Output*.  It sends the recent \
                scrollback and explains what you are looking at.  If you have text selected it becomes \
                *Explain Selection* and only that text is sent — useful for asking about one confusing \
                line rather than the whole screen.
                """),
            GuideSection (
                heading: "Diagnose",
                body: """
                *Diagnose Failure* is for when something just broke.  It sends a larger slice of \
                scrollback than Explain, because the cause of an error is usually several lines above \
                the error itself, and asks specifically why the failure happened.
                """),
            GuideSection (
                heading: "Get a Command",
                body: """
                Describe what you want in plain language and get back a single shell command, tagged \
                with a risk badge.  The command is never executed for you — it is placed where you can \
                read it, edit it and decide.  **Read the command before you run it**, especially \
                anything marked risky.
                """),
            GuideSection (
                heading: "What gets sent, and language",
                body: """
                Only the scrollback for the action you invoked leaves the device, and only to the \
                provider you configured.  Terminal contents often include hostnames, paths and \
                occasionally secrets, so treat these actions the way you would treat pasting into any \
                third-party service.

                You can control how many lines Explain and Diagnose send, and which language answers \
                come back in, from the **AI** screen.
                """),
        ]),

    GuideTopic (
        title: "Settings",
        icon: "gear",
        summary: "Themes, fonts and global behaviour",
        sections: [
            GuideSection (
                heading: "Appearance",
                body: """
                Pick a colour theme and a monospaced font.  Setting the font size to the system default \
                lets it follow Dynamic Type; any other value pins it.  Individual hosts may override the \
                theme.
                """),
            GuideSection (
                heading: "Keep Display On",
                body: """
                Prevents the screen from sleeping while you are connected.  Handy when you are watching \
                a long build, at the cost of battery.
                """),
            GuideSection (
                heading: "Beep",
                body: """
                Chooses what happens when the terminal receives a bell character: nothing, an audible \
                beep, or a vibration.
                """),
            GuideSection (
                heading: "Track Location",
                body: """
                An opt-in setting that lets the app keep running in the background so sessions stay \
                alive longer.  It records locations, which you can review under History.  Leave it off \
                unless you specifically need it.
                """),
        ]),

    GuideTopic (
        title: "Troubleshooting",
        icon: "wrench.and.screwdriver",
        summary: "When something will not connect",
        sections: [
            GuideSection (
                heading: "Connection refused",
                body: """
                Nothing is listening on that port.  Check that the SSH server is running \
                (`systemctl status sshd`) and that you have the right port — many hosts move SSH off 22.
                """),
            GuideSection (
                heading: "Connection times out",
                body: """
                The packets are not arriving at all: a firewall, security group, or simply the wrong \
                address.  Confirm the machine is reachable from the network you are on right now — a \
                host that works on your home Wi-Fi may be unreachable on cellular.
                """),
            GuideSection (
                heading: "Permission denied (publickey)",
                body: """
                The server did not accept your key.  Check that the public key really is in \
                `~/.ssh/authorized_keys`, that you attached the matching key to this host, and that the \
                permissions are right — `sshd` silently ignores `~/.ssh` if it is group- or \
                world-writable. `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`.
                """),
            GuideSection (
                heading: "Host key changed",
                body: """
                Either the server was rebuilt or reinstalled, or something is intercepting the \
                connection.  Verify out-of-band before removing the old entry from **Known Hosts**.
                """),
            GuideSection (
                heading: "Garbled characters or broken box drawing",
                body: """
                Usually a locale or TERM mismatch.  Make sure the server has a UTF-8 locale \
                (`locale` should show `UTF-8`) and that `TERM` is set to `xterm-256color`.  You can set \
                `TERM` per host in its environment variables.
                """),
            GuideSection (
                heading: "The session drops when I switch apps",
                body: """
                iOS suspends backgrounded apps, which closes the connection.  Use a host configured for \
                **tmux** reconnect so your work survives, or enable Keep Display On for short waits.
                """),
        ]),
]
