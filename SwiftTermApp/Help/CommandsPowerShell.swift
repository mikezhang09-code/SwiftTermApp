//
//  CommandsPowerShell.swift
//  SwiftTermApp
//
//  The PowerShell half of the command reference — what you get when you SSH
//  into a Windows host running OpenSSH.
//

import Foundation

let powershellCommandGroups: [CommandCategory] = [

    CommandCategory (
        name: "Navigation",
        icon: "folder",
        intro: """
        PowerShell commands are named *Verb-Noun*, which makes them long but guessable. Most have \
        short aliases, and many deliberately match the Unix names — `ls`, `cd`, `pwd` and `cat` all \
        work.

        The important difference from a Unix shell: PowerShell pipes **objects**, not text. That is \
        why you filter on properties rather than parsing strings.
        """,
        entries: [
            CommandEntry (
                command: "Get-Location",
                summary: "Print the current directory (alias: pwd)",
                detail: """
                Returns the current location as an object whose `Path` property holds the string. \
                Because PowerShell can navigate more than the filesystem — the registry and the \
                certificate store are also drives — "location" is the more accurate word than \
                "directory".
                """,
                examples: [
                    CommandExample ("Get-Location", "The current path"),
                    CommandExample ("pwd", "The familiar alias for the same thing"),
                    CommandExample ("(Get-Location).Path", "Just the string, for use elsewhere"),
                ]),

            CommandEntry (
                command: "Get-ChildItem -Force",
                summary: "List files including hidden (alias: ls, dir)",
                detail: """
                Lists the contents of a location. **-Force** includes hidden and system items — on \
                Windows, hidden is a file attribute rather than a naming convention as it is on Unix. \
                The output is a collection of objects, so it can be sorted and filtered on properties \
                without any text parsing.
                """,
                examples: [
                    CommandExample ("Get-ChildItem", "List the current directory"),
                    CommandExample ("ls -Force", "Include hidden and system files"),
                    CommandExample ("Get-ChildItem -Recurse -File", "Every file below here, no directories"),
                    CommandExample ("Get-ChildItem | Sort-Object Length -Descending", "Largest files first"),
                ]),

            CommandEntry (
                command: "Set-Location C:\\path",
                summary: "Change directory (alias: cd)",
                detail: """
                Changes the current location. Windows paths use backslashes, though PowerShell \
                accepts forward slashes too. Paths containing spaces need quoting — which, on \
                Windows, is most of them.
                """,
                examples: [
                    CommandExample ("Set-Location C:\\inetpub\\wwwroot", "Go to an absolute path"),
                    CommandExample ("cd 'C:\\Program Files'", "Quote paths containing spaces"),
                    CommandExample ("cd ..", "Up one level"),
                    CommandExample ("Set-Location -", "Back to the previous location (PowerShell 6+)"),
                ]),

            CommandEntry (
                command: "Get-PSDrive",
                summary: "List drives and their free space",
                detail: """
                Shows every PowerShell drive — the filesystem drives you expect, plus providers such \
                as the registry (`HKLM:`), environment variables (`Env:`) and certificates. For a \
                straightforward look at disk space, `Get-Volume` is easier to read.
                """,
                examples: [
                    CommandExample ("Get-PSDrive", "All drives and providers"),
                    CommandExample ("Get-PSDrive -PSProvider FileSystem", "Only real disks"),
                    CommandExample ("Get-Volume", "Clearer output for free space"),
                ]),
        ]),

    CommandCategory (
        name: "Files",
        icon: "doc",
        intro: """
        The file cmdlets share a consistent naming pattern — `Get-`, `Set-`, `New-`, `Copy-`, \
        `Move-`, `Remove-Item` — and most accept **-WhatIf**, which shows what would happen without \
        doing it.
        """,
        entries: [
            CommandEntry (
                command: "Copy-Item src dst -Recurse",
                summary: "Copy a directory recursively",
                detail: """
                Copies files or directories. **-Recurse** is required for a directory's contents. \
                Unlike its Unix counterpart, this cmdlet supports **-WhatIf**, which is worth using \
                on anything with a wildcard in it.
                """,
                examples: [
                    CommandExample ("Copy-Item file.txt backup.txt", "Copy one file"),
                    CommandExample ("Copy-Item C:\\site D:\\backup -Recurse", "Copy a directory tree"),
                    CommandExample ("Copy-Item *.log D:\\logs -WhatIf", "Preview without copying anything"),
                ]),

            CommandEntry (
                command: "Move-Item old new",
                summary: "Move or rename",
                detail: """
                Moves or renames, exactly as on Unix — renaming is moving to a new name in the same \
                place. `Rename-Item` exists too and reads more clearly when renaming is all you mean.
                """,
                examples: [
                    CommandExample ("Move-Item draft.txt final.txt", "Rename a file"),
                    CommandExample ("Move-Item *.log D:\\archive\\", "Move matching files"),
                    CommandExample ("Rename-Item old.txt new.txt", "The clearer cmdlet for renaming"),
                ]),

            CommandEntry (
                command: "Remove-Item dir -Recurse -Force",
                summary: "Delete recursively — no undo",
                detail: """
                Deletes items. **-Recurse** descends into directories and **-Force** removes hidden \
                and read-only items without prompting. This bypasses the Recycle Bin entirely: the \
                files are gone.
                """,
                examples: [
                    CommandExample ("Remove-Item file.txt", "Delete one file"),
                    CommandExample ("Remove-Item temp -Recurse -Force", "Delete a directory and its contents"),
                    CommandExample ("Remove-Item temp -Recurse -WhatIf", "List what would be deleted first"),
                ],
                caution: """
                Use **-WhatIf** before any recursive delete. There is no Recycle Bin safety net here.
                """),

            CommandEntry (
                command: "New-Item -ItemType Directory a\\b",
                summary: "Create a directory",
                detail: """
                `New-Item` creates files and directories alike, so **-ItemType** is required to say \
                which. Parent directories are created automatically, as with `mkdir -p`. **-Force** \
                keeps it quiet when the target already exists.
                """,
                examples: [
                    CommandExample ("New-Item -ItemType Directory logs", "Create a directory"),
                    CommandExample ("mkdir logs", "The familiar alias works too"),
                    CommandExample ("New-Item -ItemType File empty.txt", "Create an empty file"),
                ]),

            CommandEntry (
                command: "Get-Content file",
                summary: "Print a file (alias: cat, type)",
                detail: """
                Reads a file. By default it returns an *array of lines* rather than one string, which \
                is why it pipes so naturally into `Select-String` or `Where-Object`. **-Raw** gives \
                you the whole file as a single string when you need that instead.
                """,
                examples: [
                    CommandExample ("Get-Content app.log", "Print the file"),
                    CommandExample ("Get-Content app.log -TotalCount 20", "The first 20 lines, like head"),
                    CommandExample ("Get-Content config.json -Raw", "One string rather than an array of lines"),
                    CommandExample ("cat app.log | Select-String ERROR", "Pipe into a search"),
                ]),

            CommandEntry (
                command: "Get-Content file -Tail 50 -Wait",
                summary: "Follow a log as it grows",
                detail: """
                The PowerShell equivalent of `tail -f`. **-Tail** sets how many existing lines to \
                show and **-Wait** keeps the cmdlet running, printing new lines as they are written. \
                Ctrl-c stops it.
                """,
                examples: [
                    CommandExample ("Get-Content app.log -Tail 50", "The last 50 lines"),
                    CommandExample ("Get-Content app.log -Tail 20 -Wait", "Follow the log live"),
                    CommandExample ("Get-Content app.log -Wait | Select-String ERROR", "Follow, showing only errors"),
                ]),

            CommandEntry (
                command: "Get-Content file | Measure-Object -Line",
                summary: "Count lines",
                detail: """
                `Measure-Object` counts and does arithmetic over a pipeline. **-Line** counts lines, \
                and it will also sum or average a named property. The count lives in the `Lines` \
                property of the result rather than being printed bare.
                """,
                examples: [
                    CommandExample ("Get-Content app.log | Measure-Object -Line", "Count the lines"),
                    CommandExample ("(Get-Content app.log).Count", "Shorter, since Get-Content returns an array"),
                    CommandExample ("Get-ChildItem | Measure-Object Length -Sum", "Total size of the files here"),
                ]),

            CommandEntry (
                command: "Get-FileHash file",
                summary: "Compute a file's SHA-256",
                detail: """
                Hashes a file so you can verify a download or check whether two files are identical. \
                SHA-256 is the default; **-Algorithm** selects another. Comparing hashes is the \
                reliable way to confirm a transfer arrived intact.
                """,
                examples: [
                    CommandExample ("Get-FileHash installer.exe", "SHA-256 of a file"),
                    CommandExample ("Get-FileHash file -Algorithm MD5", "A different algorithm"),
                    CommandExample ("(Get-FileHash a).Hash -eq (Get-FileHash b).Hash", "Are two files identical?"),
                ]),
        ]),

    CommandCategory (
        name: "Searching",
        icon: "magnifyingglass",
        intro: """
        `Select-String` is PowerShell's grep, and `Get-ChildItem -Recurse` is its find. Because the \
        pipeline carries objects, you can also filter on real properties — size, date, extension — \
        instead of pattern-matching text.
        """,
        entries: [
            CommandEntry (
                command: "Select-String -Path *.log -Pattern \"text\"",
                summary: "Search inside files (the grep equivalent)",
                detail: """
                Searches file contents for a regular expression and returns match objects carrying \
                the filename, line number and matched text. Unlike grep it is case-*insensitive* by \
                default; use **-CaseSensitive** when that matters.
                """,
                examples: [
                    CommandExample ("Select-String -Path *.log -Pattern \"ERROR\"", "Search the log files here"),
                    CommandExample ("Select-String -Path . -Pattern \"api\" -Recurse", "Search a whole tree"),
                    CommandExample ("Select-String -Path app.log -Pattern \"fail\" -Context 3", "Show 3 lines of context"),
                    CommandExample ("sls -Path *.log -Pattern \"ERROR\"", "sls is the built-in alias"),
                ]),

            CommandEntry (
                command: "Get-ChildItem -Recurse -Filter *.log",
                summary: "Find files by name",
                detail: """
                Walks a tree looking for matching names. **-Filter** is applied by the filesystem \
                itself and is noticeably faster than **-Include** on large directories. Add \
                **-ErrorAction SilentlyContinue** to suppress access-denied noise when searching \
                system paths.
                """,
                examples: [
                    CommandExample ("Get-ChildItem -Recurse -Filter *.log", "Every log file below here"),
                    CommandExample ("Get-ChildItem C:\\ -Recurse -Filter web.config -ErrorAction SilentlyContinue", "Search widely, quietly"),
                    CommandExample ("Get-ChildItem -Recurse | Where-Object LastWriteTime -gt (Get-Date).AddDays(-1)", "Changed in the last day"),
                ]),

            CommandEntry (
                command: "Get-ChildItem -Recurse | Where-Object Length -gt 100MB",
                summary: "Find large files",
                detail: """
                Filters on the `Length` property, which is the size in bytes. PowerShell understands \
                `KB`, `MB` and `GB` as literal suffixes, so you can write the threshold the way you \
                say it. This is the tool for tracking down what filled a disk.
                """,
                examples: [
                    CommandExample ("Get-ChildItem -Recurse | Where-Object Length -gt 100MB", "Files over 100 MB"),
                    CommandExample ("Get-ChildItem -Recurse | Sort-Object Length -Descending | Select -First 10", "The ten largest"),
                    CommandExample ("Get-ChildItem -Recurse | Measure-Object Length -Sum", "Total size of everything below here"),
                ]),

            CommandEntry (
                command: "Get-Command name",
                summary: "Find what a command name resolves to",
                detail: """
                Looks up commands — cmdlets, functions, aliases and executables. With a wildcard it \
                becomes a discovery tool: `Get-Command *service*` lists everything related to \
                services, which is often how you find the cmdlet you needed.
                """,
                examples: [
                    CommandExample ("Get-Command Get-Process", "Where a command comes from"),
                    CommandExample ("Get-Command *service*", "Discover related commands"),
                    CommandExample ("Get-Alias ls", "What a familiar alias actually maps to"),
                ]),

            CommandEntry (
                command: "Get-Help Get-Process -Examples",
                summary: "Show usage examples for a cmdlet",
                detail: """
                PowerShell ships its own documentation. **-Examples** is usually what you want, since \
                worked examples answer the question faster than the full parameter list. \
                **-Online** opens the web version in a browser.
                """,
                examples: [
                    CommandExample ("Get-Help Get-Process -Examples", "Practical examples"),
                    CommandExample ("Get-Help Get-Process -Full", "Every parameter, in detail"),
                    CommandExample ("Update-Help", "Download the latest help content"),
                ]),
        ]),

    CommandCategory (
        name: "Processes",
        icon: "gauge",
        intro: """
        Process cmdlets return rich objects, so sorting by CPU or filtering by memory needs no text \
        parsing — you work with the properties directly.
        """,
        entries: [
            CommandEntry (
                command: "Get-Process",
                summary: "List running processes (alias: ps)",
                detail: """
                Returns every running process as an object with `Id`, `Name`, `CPU` and `WorkingSet` \
                among others. Because these are real numbers rather than columns of text, sorting and \
                filtering are exact.
                """,
                examples: [
                    CommandExample ("Get-Process", "Everything running"),
                    CommandExample ("Get-Process | Sort-Object WorkingSet -Descending | Select -First 10", "Biggest memory users"),
                    CommandExample ("Get-Process | Where-Object CPU -gt 100", "Processes that have used a lot of CPU"),
                ]),

            CommandEntry (
                command: "Get-Process name",
                summary: "Find a process by name",
                detail: """
                Filters by process name, given without the `.exe` extension. It errors if nothing \
                matches, which is useful in scripts — add **-ErrorAction SilentlyContinue** when a \
                missing process is an acceptable outcome.
                """,
                examples: [
                    CommandExample ("Get-Process w3wp", "Find IIS worker processes"),
                    CommandExample ("Get-Process *sql*", "Wildcards are allowed"),
                    CommandExample ("Get-Process node -ErrorAction SilentlyContinue", "Do not error when absent"),
                ]),

            CommandEntry (
                command: "Stop-Process -Id PID",
                summary: "Kill a process by id",
                detail: """
                Ends a process. It attempts a graceful close first where the process has a window; \
                **-Force** skips straight to termination. Windows has no direct equivalent of the \
                SIGTERM/SIGKILL distinction, so treat any `Stop-Process` as fairly abrupt.
                """,
                examples: [
                    CommandExample ("Stop-Process -Id 4321", "Stop one process by id"),
                    CommandExample ("Stop-Process -Id 4321 -WhatIf", "Confirm the target before acting"),
                    CommandExample ("Get-Process node | Stop-Process", "Pipe processes straight into the stop"),
                ]),

            CommandEntry (
                command: "Stop-Process -Name name -Force",
                summary: "Force-kill by name",
                detail: """
                Stops every process with the given name at once. That plural is the risk: on a server \
                running several application pools or Node processes, one name may match far more than \
                you intended.
                """,
                examples: [
                    CommandExample ("Stop-Process -Name node -Force", "Stop every node process"),
                    CommandExample ("Get-Process node | Select Id, Path", "Check exactly what matches first"),
                ],
                caution: "Always list the matches with `Get-Process` before force-stopping by name."),

            CommandEntry (
                command: "Get-Process | Sort-Object CPU -Descending | Select -First 10",
                summary: "Top ten CPU consumers",
                detail: """
                The idiomatic PowerShell pipeline: get objects, sort them by a property, take the \
                first few. Note that `CPU` is cumulative processor seconds since the process started, \
                not a live percentage — a long-running service can top this list while sitting idle.
                """,
                examples: [
                    CommandExample ("Get-Process | Sort-Object CPU -Descending | Select -First 10", "Ten highest by total CPU"),
                    CommandExample ("Get-Process | Sort-Object WorkingSet -Descending | Select -First 10 Name, WorkingSet", "By memory, showing two columns"),
                ]),
        ]),

    CommandCategory (
        name: "Networking",
        icon: "network",
        intro: """
        The `Net*` cmdlets replace the old `ipconfig` and `netstat` tools, and `Test-NetConnection` \
        rolls ping, port check and route lookup into one diagnostic.
        """,
        entries: [
            CommandEntry (
                command: "Get-NetIPAddress",
                summary: "Show interfaces and addresses",
                detail: """
                Lists every IP address on the machine with its interface. Filtering to IPv4 makes the \
                output far shorter, since Windows assigns a great many IPv6 addresses by default.
                """,
                examples: [
                    CommandExample ("Get-NetIPAddress -AddressFamily IPv4", "IPv4 addresses only"),
                    CommandExample ("Get-NetIPConfiguration", "Addresses, gateway and DNS together"),
                    CommandExample ("ipconfig /all", "The classic tool, still available"),
                ]),

            CommandEntry (
                command: "Get-NetTCPConnection -State Listen",
                summary: "Which ports are listening",
                detail: """
                Shows listening sockets — the Windows answer to `ss -tulpn`. It reports the owning \
                process as a PID, so join it to `Get-Process` to see which program that actually is.

                As on Unix, watch the local address: `127.0.0.1` accepts only local connections while \
                `0.0.0.0` accepts them from anywhere.
                """,
                examples: [
                    CommandExample ("Get-NetTCPConnection -State Listen", "Everything listening"),
                    CommandExample ("Get-NetTCPConnection -LocalPort 443", "Who owns port 443"),
                    CommandExample ("Get-NetTCPConnection -State Listen | Select LocalAddress, LocalPort, @{n='Process';e={(Get-Process -Id $_.OwningProcess).Name}}", "Listening ports with process names"),
                ]),

            CommandEntry (
                command: "Test-NetConnection host -Port 443",
                summary: "Can I reach this host on this port",
                detail: """
                The single best network diagnostic on Windows. It resolves the name, pings, and tests \
                the TCP port, reporting each result separately — so one command tells you whether the \
                problem is DNS, routing, or a service that simply is not listening.
                """,
                examples: [
                    CommandExample ("Test-NetConnection example.com -Port 443", "Full check against one port"),
                    CommandExample ("Test-NetConnection example.com", "Ping and route only"),
                    CommandExample ("tnc example.com -Port 443", "tnc is the alias"),
                ]),

            CommandEntry (
                command: "Resolve-DnsName example.com",
                summary: "Resolve a name",
                detail: """
                Queries DNS, the equivalent of `dig`. **-Server** asks a specific resolver, which is \
                how you tell a stale local cache apart from a genuinely wrong record.
                """,
                examples: [
                    CommandExample ("Resolve-DnsName example.com", "Resolve a hostname"),
                    CommandExample ("Resolve-DnsName example.com -Type MX", "Mail records"),
                    CommandExample ("Resolve-DnsName example.com -Server 8.8.8.8", "Bypass the local resolver"),
                    CommandExample ("Clear-DnsClientCache", "Flush the local DNS cache"),
                ]),

            CommandEntry (
                command: "Invoke-WebRequest https://example.com -OutFile f",
                summary: "Download a file",
                detail: """
                Fetches a URL. **-OutFile** saves to disk; without it you get a response object whose \
                `StatusCode`, `Headers` and `Content` you can inspect. In Windows PowerShell 5 it is \
                slow on large files because of a progress bar — setting \
                `$ProgressPreference = 'SilentlyContinue'` speeds it up dramatically.
                """,
                examples: [
                    CommandExample ("Invoke-WebRequest https://example.com/f.zip -OutFile f.zip", "Download a file"),
                    CommandExample ("(Invoke-WebRequest https://example.com).StatusCode", "Just the HTTP status"),
                    CommandExample ("iwr https://example.com -Method Head", "Headers only, like curl -I"),
                ]),

            CommandEntry (
                command: "Invoke-RestMethod https://api.example.com",
                summary: "Call a JSON API and get an object back",
                detail: """
                Like `Invoke-WebRequest`, but it parses JSON or XML responses into real objects \
                automatically. That means you can reach straight into the result with dot notation, \
                with no parsing step at all — the clearest illustration of what an object pipeline \
                buys you.
                """,
                examples: [
                    CommandExample ("Invoke-RestMethod https://api.example.com/status", "Call an API, get an object"),
                    CommandExample ("(Invoke-RestMethod https://api.example.com/users).name", "Reach into the response directly"),
                    CommandExample ("irm https://api.example.com -Method Post -Body $json -ContentType 'application/json'", "POST some JSON"),
                ]),
        ]),

    CommandCategory (
        name: "Services and Logs",
        icon: "server.rack",
        intro: """
        Windows services are the equivalent of systemd units, and the event log is the equivalent of \
        the journal — though it is structured into separate logs rather than one stream.
        """,
        entries: [
            CommandEntry (
                command: "Get-Service name",
                summary: "Is this service running",
                detail: """
                Reports a service's status and startup type. As with systemd, *running* and *starts \
                automatically* are separate facts: a service can be running now and still fail to \
                come back after a reboot.
                """,
                examples: [
                    CommandExample ("Get-Service W3SVC", "Check one service"),
                    CommandExample ("Get-Service | Where-Object Status -eq 'Running'", "Everything currently running"),
                    CommandExample ("Get-Service | Where-Object StartType -eq 'Automatic' | Where-Object Status -ne 'Running'", "Should be running, but is not"),
                ]),

            CommandEntry (
                command: "Restart-Service name",
                summary: "Restart a service",
                detail: """
                Stops and starts a service. **-Force** also restarts any dependent services, which is \
                necessary when other services depend on this one — without it the stop simply fails.
                """,
                examples: [
                    CommandExample ("Restart-Service W3SVC", "Restart a service"),
                    CommandExample ("Restart-Service W3SVC -Force", "Also restart dependent services"),
                    CommandExample ("Stop-Service W3SVC; Start-Service W3SVC", "The two steps separately"),
                ],
                caution: "Service control needs an elevated session — run PowerShell as Administrator."),

            CommandEntry (
                command: "Set-Service name -StartupType Automatic",
                summary: "Start on every boot",
                detail: """
                Sets whether a service starts at boot. `Automatic` starts immediately, \
                `AutomaticDelayedStart` waits until the system settles, `Manual` starts only on \
                demand, and `Disabled` prevents it entirely. This changes future boots only — it does \
                not start the service now.
                """,
                examples: [
                    CommandExample ("Set-Service W3SVC -StartupType Automatic", "Start at boot"),
                    CommandExample ("Set-Service W3SVC -StartupType Disabled", "Prevent it from starting"),
                    CommandExample ("Set-Service W3SVC -StartupType Automatic; Start-Service W3SVC", "Set it and start it now"),
                ]),

            CommandEntry (
                command: "Get-EventLog -LogName System -Newest 20",
                summary: "Recent system events",
                detail: """
                Reads the classic event logs — System, Application and Security. Simple and readable, \
                but it only covers the older log types and is absent from PowerShell 7 on non-Windows \
                platforms; `Get-WinEvent` is the modern replacement.
                """,
                examples: [
                    CommandExample ("Get-EventLog -LogName System -Newest 20", "Twenty most recent system events"),
                    CommandExample ("Get-EventLog -LogName System -EntryType Error -Newest 20", "Errors only"),
                    CommandExample ("Get-EventLog -LogName Application -Source MSSQLSERVER", "Events from one source"),
                ]),

            CommandEntry (
                command: "Get-WinEvent -LogName Application -MaxEvents 20",
                summary: "Recent application events",
                detail: """
                The modern event log cmdlet: faster, and able to read every log including the many \
                per-application ones. Filtering with **-FilterHashtable** is far quicker than piping \
                into `Where-Object`, because the filter is applied by the log service rather than in \
                PowerShell.
                """,
                examples: [
                    CommandExample ("Get-WinEvent -LogName Application -MaxEvents 20", "Twenty most recent events"),
                    CommandExample ("Get-WinEvent -FilterHashtable @{LogName='System'; Level=2} -MaxEvents 50", "Errors only, filtered efficiently"),
                    CommandExample ("Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddHours(-1)}", "The last hour"),
                    CommandExample ("Get-WinEvent -ListLog *", "Discover which logs exist"),
                ]),
        ]),

    CommandCategory (
        name: "System",
        icon: "desktopcomputer",
        intro: """
        Machine-level information and state. Environment variables live on the `Env:` drive, which is \
        why they are addressed as `$env:NAME`.
        """,
        entries: [
            CommandEntry (
                command: "Get-ComputerInfo",
                summary: "OS, hardware and version summary",
                detail: """
                A broad inventory: OS version and build, hardware, memory, BIOS and domain \
                membership. It is slow and verbose, so pick the properties you actually want. For \
                just the version, `$PSVersionTable` and `[System.Environment]::OSVersion` are much \
                faster.
                """,
                examples: [
                    CommandExample ("Get-ComputerInfo", "Everything, slowly"),
                    CommandExample ("Get-ComputerInfo | Select OsName, OsVersion, CsName", "Only the fields you need"),
                    CommandExample ("$PSVersionTable", "Which PowerShell version am I in?"),
                ]),

            CommandEntry (
                command: "Get-Volume",
                summary: "Disks and free space",
                detail: """
                The clearest view of disk space: drive letter, filesystem, size and remaining space. \
                This is the Windows counterpart to `df -h`.
                """,
                examples: [
                    CommandExample ("Get-Volume", "All volumes with free space"),
                    CommandExample ("Get-Volume C", "One drive"),
                    CommandExample ("Get-Volume | Where-Object SizeRemaining -lt 5GB", "Volumes running low"),
                ]),

            CommandEntry (
                command: "Get-Date",
                summary: "Current date and time",
                detail: """
                Returns a full DateTime object, so it does arithmetic as well as display. \
                `(Get-Date).AddDays(-7)` is the idiomatic way to build a cutoff for filtering logs or \
                files by age.
                """,
                examples: [
                    CommandExample ("Get-Date", "Now"),
                    CommandExample ("Get-Date -Format 'yyyy-MM-dd'", "Formatted, for filenames"),
                    CommandExample ("(Get-Date).AddDays(-7)", "A week ago, for use as a filter"),
                ]),

            CommandEntry (
                command: "Restart-Computer",
                summary: "Reboot the machine",
                detail: """
                Reboots the system. Over SSH this ends your session immediately — including any \
                unsaved work in the shell — so confirm you are on the machine you think you are. \
                **-Force** proceeds even when users are logged in.
                """,
                examples: [
                    CommandExample ("Restart-Computer", "Reboot, with a confirmation prompt"),
                    CommandExample ("Restart-Computer -Force", "Reboot regardless of logged-in users"),
                    CommandExample ("hostname", "Check which machine you are on first"),
                ],
                caution: """
                Run `hostname` first. Rebooting the wrong server is an easy mistake to make with \
                several sessions open.
                """),

            CommandEntry (
                command: "$env:PATH",
                summary: "Read an environment variable",
                detail: """
                Environment variables are exposed through the `Env:` provider, so `$env:NAME` reads \
                one. Splitting PATH on the separator makes it readable, since Windows PATH values are \
                long and semicolon-delimited.
                """,
                examples: [
                    CommandExample ("$env:PATH", "The search path"),
                    CommandExample ("$env:PATH -split ';'", "One entry per line"),
                    CommandExample ("$env:COMPUTERNAME", "The machine name"),
                    CommandExample ("Get-ChildItem Env:", "Every environment variable"),
                ]),

            CommandEntry (
                command: "$env:VAR = \"value\"",
                summary: "Set one for this session",
                detail: """
                Sets a variable for the current session and any process it launches. It disappears \
                when the session ends — making it permanent requires \
                `[Environment]::SetEnvironmentVariable` with a `Machine` or `User` scope, which needs \
                elevation for machine scope.
                """,
                examples: [
                    CommandExample ("$env:NODE_ENV = 'production'", "Set for this session"),
                    CommandExample ("[Environment]::SetEnvironmentVariable('NODE_ENV','production','Machine')", "Persist for the whole machine"),
                ],
                caution: "A permanent variable is only picked up by *new* sessions, not the current one."),
        ]),

    CommandCategory (
        name: "Archives",
        icon: "doc.zipper",
        intro: "PowerShell handles zip natively. For tar or 7z you still need an external tool.",
        entries: [
            CommandEntry (
                command: "Compress-Archive -Path dir -DestinationPath out.zip",
                summary: "Create a zip",
                detail: """
                Creates a zip archive. **-Update** adds to an existing archive and **-Force** \
                overwrites it. Note that it is memory-hungry and slow on very large inputs — for \
                multi-gigabyte archives an external tool is a better choice.
                """,
                examples: [
                    CommandExample ("Compress-Archive -Path C:\\site -DestinationPath site.zip", "Zip a directory"),
                    CommandExample ("Compress-Archive -Path *.log -DestinationPath logs.zip", "Zip matching files"),
                    CommandExample ("Compress-Archive -Path C:\\site -DestinationPath site.zip -Force", "Overwrite an existing archive"),
                ]),

            CommandEntry (
                command: "Expand-Archive in.zip -DestinationPath dir",
                summary: "Extract a zip",
                detail: """
                Extracts an archive. Always give **-DestinationPath**: without it the contents land \
                in the current directory, which can scatter files everywhere if the archive has no \
                containing folder.
                """,
                examples: [
                    CommandExample ("Expand-Archive site.zip -DestinationPath C:\\inetpub", "Extract to a specific place"),
                    CommandExample ("Expand-Archive site.zip -DestinationPath C:\\temp -Force", "Overwrite existing files"),
                ]),
        ]),

    CommandCategory (
        name: "Pipeline Basics",
        icon: "wand.and.stars",
        intro: """
        This is what makes PowerShell different from a Unix shell. A Unix pipeline passes text, so \
        every stage re-parses it; a PowerShell pipeline passes **objects** with typed properties, so \
        every stage works with real values. Learning these six cmdlets is most of learning \
        PowerShell.
        """,
        entries: [
            CommandEntry (
                command: "... | Where-Object { $_.Name -like \"*x*\" }",
                summary: "Filter objects (alias: where, ?)",
                detail: """
                Keeps only the objects matching your test. `$_` is the current object. The comparison \
                operators are words, not symbols: **-eq**, **-ne**, **-gt**, **-lt**, **-like** for \
                wildcards, **-match** for regex. Modern PowerShell also accepts the shorter \
                `Where-Object Name -like "*x*"` without braces.
                """,
                examples: [
                    CommandExample ("Get-Process | Where-Object CPU -gt 100", "The simplified form"),
                    CommandExample ("Get-Service | Where-Object { $_.Status -eq 'Stopped' }", "The full form with a script block"),
                    CommandExample ("Get-ChildItem | Where-Object { $_.Length -gt 1MB -and $_.Extension -eq '.log' }", "Two conditions combined"),
                ],
                caution: "Use `-eq`, not `=`. A single `=` assigns rather than compares."),

            CommandEntry (
                command: "... | Select-Object Name, Id",
                summary: "Pick properties (alias: select)",
                detail: """
                Chooses which properties to keep, or takes the first or last few items with \
                **-First** and **-Last**. **-ExpandProperty** returns the bare value instead of an \
                object wrapping it, which is what you want when feeding another command.
                """,
                examples: [
                    CommandExample ("Get-Process | Select Name, Id, CPU", "Keep three columns"),
                    CommandExample ("Get-Process | Select -First 5", "The first five objects"),
                    CommandExample ("Get-Process | Select -ExpandProperty Name", "Just the names, as strings"),
                    CommandExample ("Get-Process | Select *", "Every property, including hidden ones"),
                ]),

            CommandEntry (
                command: "... | Sort-Object Name",
                summary: "Sort by a property",
                detail: """
                Sorts on one or more properties. **-Descending** reverses, and **-Unique** removes \
                duplicates. Because it sorts real typed values, numbers and dates order correctly \
                rather than alphabetically as they would in a text pipeline.
                """,
                examples: [
                    CommandExample ("Get-Process | Sort-Object CPU -Descending", "Highest CPU first"),
                    CommandExample ("Get-ChildItem | Sort-Object LastWriteTime", "Oldest first"),
                    CommandExample ("Get-Process | Sort-Object Name -Unique", "Sorted and deduplicated"),
                ]),

            CommandEntry (
                command: "... | Measure-Object",
                summary: "Count, sum or average",
                detail: """
                Aggregates a pipeline. On its own it counts; given a property name plus **-Sum**, \
                **-Average**, **-Minimum** or **-Maximum** it does arithmetic. The result is an \
                object, so reach into `.Count` or `.Sum` to get the bare number.
                """,
                examples: [
                    CommandExample ("Get-Process | Measure-Object", "How many processes"),
                    CommandExample ("Get-ChildItem | Measure-Object Length -Sum", "Total bytes in this directory"),
                    CommandExample ("(Get-ChildItem | Measure-Object Length -Sum).Sum / 1GB", "That total, in gigabytes"),
                ]),

            CommandEntry (
                command: "... | Format-Table -AutoSize",
                summary: "Print as an aligned table",
                detail: """
                Controls display. **-AutoSize** sizes the columns to the content, avoiding the \
                truncation you otherwise get in a narrow terminal — which matters on a phone.

                Format cmdlets must come **last**. They emit formatting instructions rather than \
                objects, so anything piped after them receives something unusable.
                """,
                examples: [
                    CommandExample ("Get-Process | Select Name, Id | Format-Table -AutoSize", "A tidy table"),
                    CommandExample ("Get-Process | Select -First 3 | Format-List", "One property per line, easier to read on a phone"),
                    CommandExample ("Get-Process | Out-GridView", "An interactive window, on desktop Windows only"),
                ],
                caution: "Never pipe anything after `Format-Table` except `Out-*`."),

            CommandEntry (
                command: "... | ConvertTo-Json",
                summary: "Serialise objects to JSON",
                detail: """
                Converts objects to JSON, which is how you hand PowerShell output to something else. \
                **-Depth** matters: the default is shallow and silently flattens nested objects into \
                the string "System.Object", so raise it when your data has structure. \
                `ConvertFrom-Json` goes the other way.
                """,
                examples: [
                    CommandExample ("Get-Service | Select Name, Status | ConvertTo-Json", "Export as JSON"),
                    CommandExample ("Get-Process | ConvertTo-Json -Depth 5", "Deeper nesting preserved"),
                    CommandExample ("Get-Content config.json | ConvertFrom-Json", "Parse JSON into objects"),
                    CommandExample ("Get-Service | Export-Csv services.csv -NoTypeInformation", "CSV instead"),
                ]),

            CommandEntry (
                command: "... | Get-Member",
                summary: "Discover what properties an object has",
                detail: """
                The command that makes PowerShell learnable. Piping anything into `Get-Member` lists \
                every property and method that object has — so when you do not know what to filter \
                on, this tells you. Reach for it whenever you are stuck.
                """,
                examples: [
                    CommandExample ("Get-Process | Get-Member", "Everything a process object offers"),
                    CommandExample ("Get-ChildItem | Get-Member -MemberType Property", "Only the properties"),
                    CommandExample ("Get-Service | Select -First 1 | Format-List *", "See one object's actual values"),
                ]),
        ]),
]
