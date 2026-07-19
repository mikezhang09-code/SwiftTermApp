//
//  CommandReference.swift
//  SwiftTermApp
//
//  A searchable cheat sheet of common shell commands, shown under Help.
//  Two platforms are covered: Unix (Linux and macOS) and PowerShell, which is
//  what you get when you SSH into a Windows host running OpenSSH.
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

struct CommandEntry: Identifiable {
    let id = UUID ()
    let command: String
    let summary: String

    var searchText: String { command + " " + summary }
}

struct CommandCategory: Identifiable {
    let id = UUID ()
    let name: String
    let icon: String
    let entries: [CommandEntry]
}

func commandGroups (for platform: CommandPlatform) -> [CommandCategory] {
    switch platform {
    case .unix: return unixCommandGroups
    case .powershell: return powershellCommandGroups
    }
}

let unixCommandGroups: [CommandCategory] = [
    CommandCategory (name: "Navigation", icon: "folder", entries: [
        CommandEntry (command: "pwd", summary: "Print the current directory"),
        CommandEntry (command: "ls -lah", summary: "List files, long form, human sizes, including hidden"),
        CommandEntry (command: "cd -", summary: "Return to the previous directory"),
        CommandEntry (command: "tree -L 2", summary: "Show the directory tree, two levels deep"),
        CommandEntry (command: "du -sh *", summary: "Size of each item in the current directory"),
        CommandEntry (command: "df -h", summary: "Free space on each mounted filesystem"),
    ]),

    CommandCategory (name: "Files", icon: "doc", entries: [
        CommandEntry (command: "cp -r src dst", summary: "Copy a directory recursively"),
        CommandEntry (command: "mv old new", summary: "Move or rename"),
        CommandEntry (command: "rm -rf dir", summary: "Delete recursively without prompting — no undo"),
        CommandEntry (command: "mkdir -p a/b/c", summary: "Create a directory and any missing parents"),
        CommandEntry (command: "ln -s target link", summary: "Create a symbolic link"),
        CommandEntry (command: "touch file", summary: "Create an empty file, or update its timestamp"),
        CommandEntry (command: "cat file", summary: "Print a whole file"),
        CommandEntry (command: "less file", summary: "Page through a file; q to quit, / to search"),
        CommandEntry (command: "head -n 50 file", summary: "First 50 lines"),
        CommandEntry (command: "tail -f file", summary: "Follow a file as it grows — the standard way to watch a log"),
        CommandEntry (command: "wc -l file", summary: "Count lines"),
    ]),

    CommandCategory (name: "Searching", icon: "magnifyingglass", entries: [
        CommandEntry (command: "grep -rn \"text\" .", summary: "Search recursively, showing line numbers"),
        CommandEntry (command: "grep -i \"text\" file", summary: "Case-insensitive search"),
        CommandEntry (command: "grep -v \"text\" file", summary: "Show lines that do *not* match"),
        CommandEntry (command: "find . -name \"*.log\"", summary: "Find files by name"),
        CommandEntry (command: "find . -mtime -1", summary: "Files modified in the last day"),
        CommandEntry (command: "find . -size +100M", summary: "Files larger than 100 MB"),
        CommandEntry (command: "which command", summary: "Show which binary a name resolves to"),
    ]),

    CommandCategory (name: "Text Processing", icon: "text.alignleft", entries: [
        CommandEntry (command: "sed -i 's/old/new/g' file", summary: "Replace text in place throughout a file"),
        CommandEntry (command: "awk '{print $2}' file", summary: "Print the second whitespace-separated field"),
        CommandEntry (command: "sort file | uniq -c", summary: "Count how often each line occurs"),
        CommandEntry (command: "cut -d: -f1 /etc/passwd", summary: "Take a field from delimited text"),
        CommandEntry (command: "tr -d '\\r' < in > out", summary: "Strip carriage returns from a Windows file"),
        CommandEntry (command: "diff -u a b", summary: "Compare two files, unified format"),
    ]),

    CommandCategory (name: "Processes", icon: "gauge", entries: [
        CommandEntry (command: "ps aux", summary: "List every running process"),
        CommandEntry (command: "ps aux | grep name", summary: "Find a process by name"),
        CommandEntry (command: "top", summary: "Live process and CPU view; q to quit"),
        CommandEntry (command: "htop", summary: "Friendlier top, if installed"),
        CommandEntry (command: "kill PID", summary: "Ask a process to exit"),
        CommandEntry (command: "kill -9 PID", summary: "Force a process to die — last resort"),
        CommandEntry (command: "pkill -f pattern", summary: "Kill by matching the full command line"),
        CommandEntry (command: "free -h", summary: "Memory in use and available"),
        CommandEntry (command: "uptime", summary: "How long the machine has been up, and load average"),
    ]),

    CommandCategory (name: "Networking", icon: "network", entries: [
        CommandEntry (command: "ip a", summary: "Show network interfaces and addresses"),
        CommandEntry (command: "ss -tulpn", summary: "Which ports are listening, and what owns them"),
        CommandEntry (command: "ping -c 4 host", summary: "Send four pings"),
        CommandEntry (command: "curl -I https://example.com", summary: "Fetch just the response headers"),
        CommandEntry (command: "curl -O https://example.com/f", summary: "Download a file"),
        CommandEntry (command: "dig +short example.com", summary: "Resolve a name, terse output"),
        CommandEntry (command: "scp file user@host:/path", summary: "Copy a file to another machine over SSH"),
        CommandEntry (command: "rsync -avz src/ user@host:dst/", summary: "Sync directories efficiently"),
    ]),

    CommandCategory (name: "Permissions and Users", icon: "lock", entries: [
        CommandEntry (command: "chmod 644 file", summary: "Owner read/write, everyone else read"),
        CommandEntry (command: "chmod 755 script.sh", summary: "Make a script executable"),
        CommandEntry (command: "chown user:group file", summary: "Change owner and group"),
        CommandEntry (command: "sudo command", summary: "Run one command as root"),
        CommandEntry (command: "sudo -i", summary: "Open a root shell"),
        CommandEntry (command: "id", summary: "Show your user and group membership"),
        CommandEntry (command: "passwd", summary: "Change your password"),
    ]),

    CommandCategory (name: "Services and Logs", icon: "server.rack", entries: [
        CommandEntry (command: "systemctl status name", summary: "Is this service running, and why not"),
        CommandEntry (command: "systemctl restart name", summary: "Restart a service"),
        CommandEntry (command: "systemctl enable --now name", summary: "Start now and on every boot"),
        CommandEntry (command: "journalctl -u name -f", summary: "Follow one service's log live"),
        CommandEntry (command: "journalctl -p err -b", summary: "Errors since the last boot"),
        CommandEntry (command: "dmesg | tail", summary: "Recent kernel messages"),
    ]),

    CommandCategory (name: "Packages", icon: "shippingbox", entries: [
        CommandEntry (command: "apt update && apt upgrade", summary: "Debian/Ubuntu: refresh and install updates"),
        CommandEntry (command: "apt install package", summary: "Debian/Ubuntu: install"),
        CommandEntry (command: "dnf install package", summary: "Fedora/RHEL: install"),
        CommandEntry (command: "apk add package", summary: "Alpine: install"),
        CommandEntry (command: "brew install package", summary: "macOS: install with Homebrew"),
    ]),

    CommandCategory (name: "Archives", icon: "doc.zipper", entries: [
        CommandEntry (command: "tar -czf out.tar.gz dir", summary: "Create a gzipped tarball"),
        CommandEntry (command: "tar -xzf in.tar.gz", summary: "Extract a gzipped tarball"),
        CommandEntry (command: "tar -tzf in.tar.gz", summary: "List contents without extracting"),
        CommandEntry (command: "zip -r out.zip dir", summary: "Create a zip archive"),
        CommandEntry (command: "unzip in.zip", summary: "Extract a zip archive"),
    ]),

    CommandCategory (name: "Shell Tricks", icon: "wand.and.stars", entries: [
        CommandEntry (command: "!!", summary: "Repeat the previous command"),
        CommandEntry (command: "sudo !!", summary: "Repeat the previous command as root"),
        CommandEntry (command: "history | grep text", summary: "Find something you ran earlier"),
        CommandEntry (command: "command &", summary: "Run in the background"),
        CommandEntry (command: "nohup command &", summary: "Keep running after you disconnect"),
        CommandEntry (command: "command > out 2>&1", summary: "Send output and errors to a file"),
        CommandEntry (command: "export VAR=value", summary: "Set an environment variable for this session"),
        CommandEntry (command: "Ctrl-C", summary: "Interrupt what is running"),
        CommandEntry (command: "Ctrl-D", summary: "End of input, or log out"),
        CommandEntry (command: "Ctrl-R", summary: "Search backwards through your history"),
    ]),

    CommandCategory (name: "tmux", icon: "rectangle.split.3x1", entries: [
        CommandEntry (command: "tmux new -s name", summary: "Start a named session"),
        CommandEntry (command: "tmux attach -t name", summary: "Reattach after a disconnect"),
        CommandEntry (command: "tmux ls", summary: "List sessions"),
        CommandEntry (command: "Ctrl-B d", summary: "Detach, leaving everything running"),
        CommandEntry (command: "Ctrl-B c", summary: "New window"),
        CommandEntry (command: "Ctrl-B \"", summary: "Split horizontally"),
        CommandEntry (command: "Ctrl-B %", summary: "Split vertically"),
    ]),
]

let powershellCommandGroups: [CommandCategory] = [
    CommandCategory (name: "Navigation", icon: "folder", entries: [
        CommandEntry (command: "Get-Location", summary: "Print the current directory (alias: pwd)"),
        CommandEntry (command: "Get-ChildItem -Force", summary: "List files including hidden (alias: ls, dir)"),
        CommandEntry (command: "Set-Location C:\\path", summary: "Change directory (alias: cd)"),
        CommandEntry (command: "Get-PSDrive", summary: "List drives and their free space"),
    ]),

    CommandCategory (name: "Files", icon: "doc", entries: [
        CommandEntry (command: "Copy-Item src dst -Recurse", summary: "Copy a directory recursively"),
        CommandEntry (command: "Move-Item old new", summary: "Move or rename"),
        CommandEntry (command: "Remove-Item dir -Recurse -Force", summary: "Delete recursively — no undo"),
        CommandEntry (command: "New-Item -ItemType Directory a\\b", summary: "Create a directory"),
        CommandEntry (command: "Get-Content file", summary: "Print a file (alias: cat, type)"),
        CommandEntry (command: "Get-Content file -Tail 50 -Wait", summary: "Follow a log as it grows"),
        CommandEntry (command: "Get-Content file | Measure-Object -Line", summary: "Count lines"),
        CommandEntry (command: "Get-FileHash file", summary: "Compute a file's SHA-256"),
    ]),

    CommandCategory (name: "Searching", icon: "magnifyingglass", entries: [
        CommandEntry (command: "Select-String -Path *.log -Pattern \"text\"", summary: "Search inside files (the grep equivalent)"),
        CommandEntry (command: "Get-ChildItem -Recurse -Filter *.log", summary: "Find files by name"),
        CommandEntry (command: "Get-ChildItem -Recurse | Where-Object Length -gt 100MB", summary: "Find large files"),
        CommandEntry (command: "Get-Command name", summary: "Find what a command name resolves to"),
        CommandEntry (command: "Get-Help Get-Process -Examples", summary: "Show usage examples for a cmdlet"),
    ]),

    CommandCategory (name: "Processes", icon: "gauge", entries: [
        CommandEntry (command: "Get-Process", summary: "List running processes (alias: ps)"),
        CommandEntry (command: "Get-Process name", summary: "Find a process by name"),
        CommandEntry (command: "Stop-Process -Id PID", summary: "Kill a process by id"),
        CommandEntry (command: "Stop-Process -Name name -Force", summary: "Force-kill by name"),
        CommandEntry (command: "Get-Process | Sort-Object CPU -Descending | Select -First 10", summary: "Top ten CPU consumers"),
    ]),

    CommandCategory (name: "Networking", icon: "network", entries: [
        CommandEntry (command: "Get-NetIPAddress", summary: "Show interfaces and addresses"),
        CommandEntry (command: "Get-NetTCPConnection -State Listen", summary: "Which ports are listening"),
        CommandEntry (command: "Test-NetConnection host -Port 443", summary: "Can I reach this host on this port"),
        CommandEntry (command: "Resolve-DnsName example.com", summary: "Resolve a name"),
        CommandEntry (command: "Invoke-WebRequest https://example.com -OutFile f", summary: "Download a file"),
        CommandEntry (command: "Invoke-RestMethod https://api.example.com", summary: "Call a JSON API and get an object back"),
    ]),

    CommandCategory (name: "Services and Logs", icon: "server.rack", entries: [
        CommandEntry (command: "Get-Service name", summary: "Is this service running"),
        CommandEntry (command: "Restart-Service name", summary: "Restart a service"),
        CommandEntry (command: "Set-Service name -StartupType Automatic", summary: "Start on every boot"),
        CommandEntry (command: "Get-EventLog -LogName System -Newest 20", summary: "Recent system events"),
        CommandEntry (command: "Get-WinEvent -LogName Application -MaxEvents 20", summary: "Recent application events"),
    ]),

    CommandCategory (name: "System", icon: "desktopcomputer", entries: [
        CommandEntry (command: "Get-ComputerInfo", summary: "OS, hardware and version summary"),
        CommandEntry (command: "Get-Volume", summary: "Disks and free space"),
        CommandEntry (command: "Get-Date", summary: "Current date and time"),
        CommandEntry (command: "Restart-Computer", summary: "Reboot the machine"),
        CommandEntry (command: "$env:PATH", summary: "Read an environment variable"),
        CommandEntry (command: "$env:VAR = \"value\"", summary: "Set one for this session"),
    ]),

    CommandCategory (name: "Archives", icon: "doc.zipper", entries: [
        CommandEntry (command: "Compress-Archive -Path dir -DestinationPath out.zip", summary: "Create a zip"),
        CommandEntry (command: "Expand-Archive in.zip -DestinationPath dir", summary: "Extract a zip"),
    ]),

    CommandCategory (name: "Pipeline Basics", icon: "wand.and.stars", entries: [
        CommandEntry (command: "... | Where-Object { $_.Name -like \"*x*\" }", summary: "Filter objects (alias: where, ?)"),
        CommandEntry (command: "... | Select-Object Name, Id", summary: "Pick properties (alias: select)"),
        CommandEntry (command: "... | Sort-Object Name", summary: "Sort by a property"),
        CommandEntry (command: "... | Measure-Object", summary: "Count, sum or average"),
        CommandEntry (command: "... | Format-Table -AutoSize", summary: "Print as an aligned table"),
        CommandEntry (command: "... | ConvertTo-Json", summary: "Serialise objects to JSON"),
        CommandEntry (command: "... | Get-Member", summary: "Discover what properties an object has"),
    ]),
]
