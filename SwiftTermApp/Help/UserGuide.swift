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
                blocks: [
                    .prose ("""
                    Connecting to a host does not close the others.  {terminal} **Terminals** on the \
                    home screen lists everything running, with a live count beside it, and lets you \
                    jump back to a session or close it.
                    """),
                    .prose ("""
                    When nothing is connected it says *No active sessions*, and shows **Recent \
                    Connections** so you can pick up where you left off.
                    """),
                ]),

            GuideSection (
                heading: "Surviving a dropped connection",
                blocks: [
                    .prose ("""
                    Mobile links drop — you walk into a lift, or iOS suspends the app when you switch \
                    away.  Without help, the shell dies and anything running in it dies too.
                    """),
                    .prose ("""
                    Editing a host reveals a **Restoration** row with **none** and **tmux**.  Choose \
                    **tmux** and the app attaches to a tmux session on the server, so your work \
                    survives the drop and is waiting when you reconnect.
                    """),
                    .tip ("""
                    This needs tmux installed on the server.  The **tmux** section of the Command \
                    Reference covers driving it by hand.
                    """),
                ]),

            GuideSection (
                heading: "Per-host appearance",
                blocks: [
                    .prose ("""
                    A host can override the global theme from its **Appearance** section — useful as a \
                    standing signal that you are on production.  Leave it on *Default* to follow \
                    {gear} **Settings**.
                    """),
                ]),

            GuideSection (
                heading: "Environment variables",
                blocks: [
                    .prose ("""
                    Under **Other Options**, a host can carry environment variables sent when the \
                    session opens.  This is where to set `TERM` or `LANG` when a server needs them \
                    spelled out.
                    """),
                ]),

            GuideSection (
                heading: "History",
                blocks: [
                    .prose ("""
                    {clock} **History** records past connections, so you can see when you last reached \
                    a machine.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "SSH Keys and Known Hosts",
        icon: "key",
        summary: "Creating, importing and trusting keys",
        sections: [
            GuideSection (
                heading: "Three ways to get a key",
                blocks: [
                    .prose ("Open {key} **Keys** from the home screen.  You can:"),
                    .bullets ([
                        "**Generate** one — pick **ed25519** or **RSA**.  ed25519 is the better default: short, fast and secure.  RSA is there for older servers, at 1024, 2048 or 4096 bits.",
                        "**Create a Secure Enclave key** — an `ecdsa-sha2-nistp256` key whose private half is generated inside the device's Secure Enclave and can never be extracted, not even by the app.",
                        "**Import** one you already use — paste it, or pick the file with the Files browser.  The private key is required; a passphrase is asked for if it needs one.",
                    ]),
                    .tip ("""
                    The Secure Enclave option is the strongest choice available on the device.  The \
                    trade-off is that the key cannot be backed up or copied to another machine — if \
                    you lose the device, you enrol a new key.
                    """),
                ]),

            GuideSection (
                heading: "Putting the key on the server",
                blocks: [
                    .prose ("""
                    Copy the **public** key from its detail page and append it to `authorized_keys` \
                    on the server.  From a session you already have:
                    """),
                    .terminal ([
                        "$ mkdir -p ~/.ssh && chmod 700 ~/.ssh",
                        "$ echo 'ssh-ed25519 AAAA...' >> ~/.ssh/authorized_keys",
                        "$ chmod 600 ~/.ssh/authorized_keys",
                    ]),
                    .prose ("""
                    Those permissions are not decoration: `sshd` silently ignores `~/.ssh` if it is \
                    group- or world-writable, which produces a *Permission denied* that looks \
                    inexplicable.
                    """),
                    .tip ("Never paste the *private* key anywhere.  Only the public half leaves the device."),
                ]),

            GuideSection (
                heading: "Known Hosts",
                blocks: [
                    .prose ("""
                    {lock.desktopcomputer} **Known Hosts** lists the server fingerprints you have \
                    accepted, each with its endpoint, key type and key.  They are checked on every \
                    connection so a machine cannot be swapped behind your back.
                    """),
                    .prose ("""
                    If a fingerprint changes you get a warning.  Usually the server was rebuilt or \
                    reinstalled — but it can also mean something is intercepting the connection.
                    """),
                    .tip ("""
                    Verify by some other route before deleting the old entry.  Removing the warning \
                    is easy; noticing that you should not have is the hard part.
                    """),
                ]),
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
                blocks: [
                    .prose ("""
                    A snippet is a saved block of one or more commands.  Rather than retype a long \
                    invocation on a phone keyboard, save it once and paste it whenever you need it.
                    """),
                    .prose ("""
                    Unlike shell history, snippets are yours rather than a server's: they follow you \
                    to every host and survive rebuilds.
                    """),
                ]),

            GuideSection (
                heading: "Creating one",
                blocks: [
                    .steps ([
                        "Tap {note.text} **Snippets** on the home screen.",
                        "Tap **Add Snippet**.",
                        "Give it a **Title** — this is what you will pick from the list.",
                        "Type the commands in **Command**.",
                        "Tap **Save**.  It stays disabled until both fields have something in them.",
                    ]),
                ]),

            GuideSection (
                heading: "Running several commands",
                blocks: [
                    .prose ("""
                    Put each command on its own line in the **Command** box — pressing return there \
                    inserts a newline rather than saving.  A snippet holding:
                    """),
                    .terminal ([
                        "ls",
                        "cd ..",
                    ]),
                    .prose ("runs both, in order, exactly as if you had typed them:"),
                    .terminal ([
                        "$ ls",
                        "Documents    Downloads",
                        "$ cd ..",
                        "$ ",
                    ]),
                ]),

            GuideSection (
                heading: "Using one",
                blocks: [
                    .prose ("""
                    In a session — SSH or the Local Terminal — tap {note.text} in the toolbar and \
                    choose your snippet.  The picker has a search field, which earns its keep once \
                    you have more than a handful.
                    """),
                ]),

            GuideSection (
                heading: "The trailing newline decides whether it runs",
                blocks: [
                    .bullets ([
                        "**Ending with a newline** — every line runs immediately, including the last.",
                        "**No trailing newline** — the earlier lines run and the last one waits at the prompt, where you can read or edit it before pressing return.",
                    ]),
                    .tip ("""
                    For anything destructive, leave the newline off on purpose.  That pause is your \
                    last chance to notice you are on the wrong server.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Port Forwarding",
        icon: "arrow.left.arrow.right",
        summary: "Tunnelling ports over your SSH connection",
        sections: [
            GuideSection (
                heading: "What forwarding is for",
                blocks: [
                    .prose ("""
                    A forward carries a network port through your SSH connection, letting you reach \
                    something that is not exposed to the internet — a database bound to the server's \
                    loopback, or an admin page behind a firewall.
                    """),
                    .prose ("""
                    Open {arrow.left.arrow.right} in a connected terminal's toolbar.  Forwards live \
                    as long as the session does.
                    """),
                ]),

            GuideSection (
                heading: "The three kinds",
                blocks: [
                    .prose ("Tap **+** to add one, and pick a **Type**:"),
                    .bullets ([
                        "**Local (-L)** — the common one.  Tunnels a port on *this device* to something the server can reach.",
                        "**Dynamic SOCKS (-D)** — turns the connection into a SOCKS5 proxy on the device, so anything the server can reach becomes browsable.",
                        "**Remote (-R)** — the mirror image: opens a port on the *server* that forwards back to something this device can reach.",
                    ]),
                    .tip ("""
                    The form relabels its fields as you switch type — *Listen on this device port* \
                    becomes *Server listens on port* for Remote — so read the headings rather than \
                    assuming which end is which.
                    """),
                ]),

            GuideSection (
                heading: "Example: reaching a private database",
                blocks: [
                    .prose ("""
                    Say Postgres listens on `127.0.0.1:5432` on the server and refuses outside \
                    connections.  Add a **Local (-L)** forward listening on device port `5432`, \
                    forwarding to `127.0.0.1:5432` as seen from the server.
                    """),
                    .prose ("""
                    Anything on the device pointed at `localhost:5432` now lands on the server's \
                    database, with the traffic encrypted inside your SSH connection.
                    """),
                ]),

            GuideSection (
                heading: "Browsing through the tunnel",
                blocks: [
                    .prose ("""
                    A **Dynamic SOCKS** forward comes with a built-in **Proxied Browser**, which shows \
                    {lock.shield} *via SOCKS 127.0.0.1:port* while it is routing through the server.
                    """),
                    .prose ("""
                    It is the quickest way to open an internal site without setting up a VPN.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "AI Assistance",
        icon: "sparkles",
        summary: "Explain, Diagnose and command suggestions",
        sections: [
            GuideSection (
                heading: "Setting it up",
                blocks: [
                    .steps ([
                        "Tap {sparkles} **AI** on the home screen.",
                        "Add a provider and paste your API key.  It is stored in the keychain, never in settings files.",
                        "Optionally tap **Test** to confirm the key and model work.",
                        "The provider with the checkmark is the one the AI features use.",
                    ]),
                    .prose ("""
                    Each provider carries a **Kind**, an **Endpoint** you can repoint at a compatible \
                    proxy or gateway, and a **Model**.
                    """),
                ]),

            GuideSection (
                heading: "The three actions",
                blocks: [
                    .prose ("The {sparkles} menu in a terminal offers:"),
                    .bullets ([
                        "{text.magnifyingglass} **Explain Output** — sends recent scrollback and explains what you are looking at.  Select text first and it becomes *Explain Selection*, sending only that.",
                        "{stethoscope} **Diagnose Failure** — for when something just broke.  Sends more scrollback than Explain, because the cause usually sits several lines above the error.",
                        "{wand.and.stars} **Get a Command** — describe what you want in plain language and get one shell command back.",
                    ]),
                ]),

            GuideSection (
                heading: "Command suggestions carry a risk badge",
                blocks: [
                    .prose ("A suggested command is labelled with how dangerous it is:"),
                    .bullets ([
                        "**safe** — reads state without changing anything.",
                        "**caution** — changes something.",
                        "**destructive** — can lose data.  Inserting one raises a confirmation you have to accept deliberately.",
                    ]),
                    .prose ("""
                    Nothing is ever executed for you.  The command is placed at the prompt for you to \
                    read, edit and decide on.
                    """),
                    .tip ("""
                    Treat the badge as a prompt to think, not a guarantee.  A command marked *safe* \
                    is still a command someone else wrote, aimed at your server.
                    """),
                ]),

            GuideSection (
                heading: "What leaves the device",
                blocks: [
                    .prose ("""
                    Only the scrollback for the action you invoked, and only to the provider you \
                    configured.  Nothing is sent in the background.
                    """),
                    .prose ("""
                    Terminal output routinely contains hostnames, paths, usernames and sometimes \
                    secrets, so treat these actions the way you would treat pasting into any \
                    third-party service.
                    """),
                    .prose ("""
                    Under **Answers** you can set the **Answer language**, and how many lines of \
                    context **Explain** and **Diagnose** each send.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Settings",
        icon: "gear",
        summary: "Themes, fonts and global behaviour",
        sections: [
            GuideSection (
                heading: "Appearance",
                blocks: [
                    .prose ("""
                    {gear} **Settings** holds the defaults every session starts from: a colour \
                    **Theme**, a monospaced **Font**, and a **Font Size**.
                    """),
                    .tip ("""
                    Leaving the size on the system default lets the terminal follow Dynamic Type, so \
                    it tracks the text size you use everywhere else.  Any other value pins it.
                    """),
                    .prose ("Individual hosts can override the theme; pinching in a terminal overrides the size for that session."),
                ]),

            GuideSection (
                heading: "Keep Display On",
                blocks: [
                    .prose ("""
                    Stops the screen sleeping while you are connected — worth it when you are watching \
                    a long build, at the cost of battery.
                    """),
                ]),

            GuideSection (
                heading: "Beep",
                blocks: [
                    .prose ("Chooses what happens when the terminal receives a bell character:"),
                    .bullets ([
                        "**Silent** — nothing.",
                        "**Beep** — an audible tone.",
                        "**Vibrate** — a haptic tap, the default.",
                    ]),
                ]),

            GuideSection (
                heading: "Track Location",
                blocks: [
                    .prose ("""
                    Opt-in, and off by default.  It lets the app keep running in the background so \
                    sessions stay alive longer, at the cost of recording locations, which you can \
                    review under {clock} **History**.
                    """),
                    .tip ("""
                    Leave this off unless you specifically need it.  For keeping work alive across \
                    disconnects, a host set to **tmux** restoration is both more reliable and less \
                    invasive.
                    """),
                ]),
        ]),

    GuideTopic (
        title: "Troubleshooting",
        icon: "wrench.and.screwdriver",
        summary: "When something will not connect",
        sections: [
            GuideSection (
                heading: "Connection refused",
                blocks: [
                    .prose ("""
                    Something answered and said no — nothing is listening on that port.  The machine \
                    is up and reachable, so this is about the service, not the network.
                    """),
                    .terminal ([
                        "$ systemctl status sshd",
                        "  Active: active (running)",
                        "$ ss -tulpn | grep :22",
                    ]),
                    .prose ("""
                    Also check the port itself: plenty of servers move SSH off 22, and the app's \
                    **Port** field lives under **Other Options** when editing a host.
                    """),
                ]),

            GuideSection (
                heading: "Connection times out",
                blocks: [
                    .prose ("""
                    Nothing answered at all — a firewall, a cloud security group, or simply the wrong \
                    address.  Confirm the machine is reachable from the network you are on *now*: a \
                    host that works on home Wi-Fi may be unreachable on cellular.
                    """),
                ]),

            GuideSection (
                heading: "Permission denied (publickey)",
                blocks: [
                    .prose ("The server did not accept your key.  In order of likelihood:"),
                    .steps ([
                        "The public key is not in `~/.ssh/authorized_keys` on the server.",
                        "A different key is attached to this host in the app.",
                        "The permissions are wrong — `sshd` ignores `~/.ssh` if it is group- or world-writable.",
                    ]),
                    .terminal ([
                        "$ chmod 700 ~/.ssh",
                        "$ chmod 600 ~/.ssh/authorized_keys",
                    ]),
                ]),

            GuideSection (
                heading: "Host key changed",
                blocks: [
                    .prose ("""
                    Either the server was rebuilt, or something is intercepting the connection. \
                    Verify by another route before removing the old entry from \
                    {lock.desktopcomputer} **Known Hosts**.
                    """),
                ]),

            GuideSection (
                heading: "Garbled characters or broken boxes",
                blocks: [
                    .prose ("Usually a locale or `TERM` mismatch.  Check both:"),
                    .terminal ([
                        "$ locale",
                        "LANG=en_US.UTF-8",
                        "$ echo $TERM",
                        "xterm-256color",
                    ]),
                    .prose ("""
                    If they are wrong, set them per host under **Other Options** → **Environment \
                    Variables**.
                    """),
                ]),

            GuideSection (
                heading: "The session drops when I switch apps",
                blocks: [
                    .prose ("""
                    iOS suspends backgrounded apps, which closes the connection.  This is the \
                    platform working as designed, not a fault.
                    """),
                    .prose ("""
                    Set the host's **Restoration** to **tmux** so your work survives and resumes on \
                    reconnect.  For short waits, **Keep Display On** in {gear} **Settings** avoids \
                    the sleep that triggers it.
                    """),
                ]),
        ]),
]
