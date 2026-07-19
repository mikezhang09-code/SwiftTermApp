//
//  CommandsUnix.swift
//  SwiftTermApp
//
//  The Linux / macOS half of the command reference.  Entries carry an
//  explanation and worked examples, not just a one-line gloss, so the reference
//  teaches rather than merely reminds.
//

import Foundation

let unixCommandGroups: [CommandCategory] = [

    CommandCategory (
        name: "Navigation",
        icon: "folder",
        intro: """
        The shell always has a "current directory", and most commands act on it unless you say \
        otherwise. These commands tell you where you are and move you around.
        """,
        entries: [
            CommandEntry (
                command: "pwd",
                summary: "Print the current directory",
                detail: """
                Short for *print working directory*. Your prompt often shows an abbreviated path \
                (`~` means your home directory), so `pwd` is how you get the unambiguous, absolute \
                answer — useful before you run something destructive.
                """,
                examples: [
                    CommandExample ("pwd", "Prints something like /home/mike/projects"),
                    CommandExample ("basename $(pwd)", "Just the current directory's name, without the path"),
                ]),

            CommandEntry (
                command: "ls -lah",
                summary: "List files, long form, human sizes, including hidden",
                detail: """
                `ls` lists a directory. The flags stack up and are worth knowing individually: \
                **-l** gives the long form (permissions, owner, size, date), **-a** includes hidden \
                files — on Unix a file is hidden simply by starting with a dot — and **-h** prints \
                sizes as 4.0K or 2.3G instead of raw bytes.
                """,
                examples: [
                    CommandExample ("ls", "Bare names, in columns"),
                    CommandExample ("ls -lah", "The everyday combination: everything, readable"),
                    CommandExample ("ls -lt", "Newest first — what changed most recently"),
                    CommandExample ("ls -lS", "Largest first — what is eating the disk"),
                    CommandExample ("ls -d */", "Only directories, not the files"),
                ]),

            CommandEntry (
                command: "cd -",
                summary: "Return to the previous directory",
                detail: """
                `cd` changes directory; the lone `-` is a shortcut meaning *the directory I was in \
                before this one*. It toggles, so running it twice puts you back. This saves a lot of \
                typing when you are bouncing between a config directory and a log directory.
                """,
                examples: [
                    CommandExample ("cd /var/log", "Go to an absolute path"),
                    CommandExample ("cd ..", "Up one level"),
                    CommandExample ("cd", "With no argument, go to your home directory"),
                    CommandExample ("cd -", "Back to wherever you just were"),
                ]),

            CommandEntry (
                command: "tree -L 2",
                summary: "Show the directory tree, two levels deep",
                detail: """
                Draws the directory structure as an indented tree. **-L** limits the depth, which you \
                almost always want — without it, one `tree` in the wrong place will scroll for \
                thousands of lines. Not installed everywhere; `find` can stand in for it.
                """,
                examples: [
                    CommandExample ("tree -L 2", "Two levels down from here"),
                    CommandExample ("tree -L 2 -d", "Directories only — a quick map of a new project"),
                    CommandExample ("find . -maxdepth 2 -type d", "The same idea when tree is not installed"),
                ]),

            CommandEntry (
                command: "du -sh *",
                summary: "Size of each item in the current directory",
                detail: """
                *Disk usage*. **-s** summarises each argument into a single total instead of listing \
                every file underneath, and **-h** makes the numbers human-readable. This is the tool \
                for the question "what is filling this disk?" — run it, find the biggest entry, `cd` \
                into it, and repeat until you find the culprit.
                """,
                examples: [
                    CommandExample ("du -sh *", "Size of every item here"),
                    CommandExample ("du -sh * | sort -h", "Same, sorted smallest to largest"),
                    CommandExample ("du -sh .", "One total for the current directory"),
                ],
                caution: """
                On a large tree this walks every file and can take a while. It also skips other \
                filesystems' contents in some cases, so its total may not match `df`.
                """),

            CommandEntry (
                command: "df -h",
                summary: "Free space on each mounted filesystem",
                detail: """
                Where `du` measures directories, `df` measures whole filesystems. When something \
                fails with "no space left on device", this is the first command to run — check the \
                **Use%** column. Note that a filesystem can also fail while showing free space if it \
                has run out of *inodes*, which `df -i` reveals.
                """,
                examples: [
                    CommandExample ("df -h", "Space on every mounted filesystem"),
                    CommandExample ("df -h .", "Just the filesystem holding the current directory"),
                    CommandExample ("df -i", "Inode usage — the other way to run out of space"),
                ]),
        ]),

    CommandCategory (
        name: "Files",
        icon: "doc",
        intro: """
        Creating, moving and reading files. Note that Unix tools generally do what you asked without \
        confirming, so the flags that add safety are worth building into your habits.
        """,
        entries: [
            CommandEntry (
                command: "cp -r src dst",
                summary: "Copy a directory recursively",
                detail: """
                `cp` copies files; **-r** (recursive) is required for directories, since by default \
                `cp` refuses to copy one. A trailing slash on the source matters to some tools but \
                not to `cp` — what matters here is whether the destination already exists: if `dst` \
                is an existing directory, `src` is copied *inside* it.
                """,
                examples: [
                    CommandExample ("cp file.txt backup.txt", "Copy a single file"),
                    CommandExample ("cp -r site/ /var/www/", "Copy a whole directory"),
                    CommandExample ("cp -a src dst", "Archive mode: preserves permissions, timestamps and links"),
                    CommandExample ("cp -i file dst", "Prompt before overwriting anything"),
                ],
                caution: "Without **-i**, `cp` silently overwrites an existing destination file."),

            CommandEntry (
                command: "mv old new",
                summary: "Move or rename",
                detail: """
                There is no separate rename command on Unix: moving a file to a new name in the same \
                directory *is* renaming it. Within one filesystem `mv` is instant regardless of file \
                size, because only the directory entry changes; across filesystems it becomes a real \
                copy-then-delete and takes time.
                """,
                examples: [
                    CommandExample ("mv draft.txt final.txt", "Rename in place"),
                    CommandExample ("mv *.log archive/", "Move every log file into a directory"),
                    CommandExample ("mv -i a b", "Prompt before clobbering an existing b"),
                    CommandExample ("mv -n a b", "Never overwrite; do nothing if b exists"),
                ],
                caution: "Like `cp`, `mv` overwrites the destination without asking unless you pass **-i** or **-n**."),

            CommandEntry (
                command: "rm -rf dir",
                summary: "Delete recursively without prompting — no undo",
                detail: """
                `rm` removes files. **-r** recurses into directories and **-f** forces, suppressing \
                prompts and errors about files that do not exist. There is no trash and no undo: the \
                data is gone, and on a server there may be no backup either.
                """,
                examples: [
                    CommandExample ("rm file.txt", "Delete one file"),
                    CommandExample ("rm -i *.tmp", "Delete with a prompt for each file"),
                    CommandExample ("rm -r olddir", "Delete a directory, prompting on protected files"),
                    CommandExample ("rm -rf node_modules", "The usual reason people reach for -rf"),
                ],
                caution: """
                Check the path before pressing return, especially with a variable in it — if the \
                variable is empty, `rm -rf $DIR/` becomes `rm -rf /`. Prefer `ls` on the same path \
                first to confirm you are pointed where you think.
                """),

            CommandEntry (
                command: "mkdir -p a/b/c",
                summary: "Create a directory and any missing parents",
                detail: """
                Without **-p**, `mkdir` fails if the parent does not exist, and fails again if the \
                directory already exists. With **-p** it creates the whole chain and stays silent \
                when everything is already there — which makes it safe to run in scripts.
                """,
                examples: [
                    CommandExample ("mkdir logs", "One directory here"),
                    CommandExample ("mkdir -p ~/projects/app/src", "Create the full path in one go"),
                    CommandExample ("mkdir -m 700 private", "Create with specific permissions"),
                ]),

            CommandEntry (
                command: "ln -s target link",
                summary: "Create a symbolic link",
                detail: """
                A symbolic link is a small file that points at another path — like an alias or \
                shortcut. **-s** makes it symbolic; without it you get a *hard* link, which is a \
                second name for the same data and cannot span filesystems or point at directories. \
                The order is easy to get backwards: the existing thing comes first.
                """,
                examples: [
                    CommandExample ("ln -s /opt/app/v2 /opt/app/current", "Point a stable name at a versioned directory"),
                    CommandExample ("ls -l /opt/app/current", "Shows the link and where it points, with an arrow"),
                    CommandExample ("readlink -f current", "Resolve a link to its final real path"),
                ],
                caution: """
                A symlink to a relative path is resolved from the link's own location, not from where \
                you created it. Using absolute targets avoids a class of confusing breakage.
                """),

            CommandEntry (
                command: "touch file",
                summary: "Create an empty file, or update its timestamp",
                detail: """
                If the file does not exist, `touch` creates it empty; if it does, `touch` updates its \
                modification time and leaves the contents alone. Both behaviours get used — the first \
                to create a placeholder or a flag file, the second to make a build tool think \
                something changed.
                """,
                examples: [
                    CommandExample ("touch .gitkeep", "Create an empty placeholder file"),
                    CommandExample ("touch a b c", "Create several at once"),
                    CommandExample ("touch -d '2 hours ago' file", "Set a specific modification time"),
                ]),

            CommandEntry (
                command: "cat file",
                summary: "Print a whole file",
                detail: """
                Short for *concatenate*: given several files it prints them one after another, which \
                is how it got the name. For a short config file it is the quickest way to see \
                everything at once. For anything long, use `less` instead so you can scroll.
                """,
                examples: [
                    CommandExample ("cat /etc/hostname", "Print a short file"),
                    CommandExample ("cat -n script.sh", "Print with line numbers"),
                    CommandExample ("cat a.txt b.txt > combined.txt", "Join two files into a third"),
                ],
                caution: """
                Running `cat` on a binary file floods the terminal with control characters and can \
                leave it displaying garbage. If that happens, type `reset` and press return.
                """),

            CommandEntry (
                command: "less file",
                summary: "Page through a file; q to quit, / to search",
                detail: """
                An interactive pager: it loads the file lazily, so it opens instantly even on a \
                multi-gigabyte log. Inside it, **space** pages down, **b** pages back, **/text** \
                searches forwards, **n** jumps to the next match, **G** goes to the end, **g** to the \
                start, and **q** quits.
                """,
                examples: [
                    CommandExample ("less /var/log/syslog", "Open a log for reading"),
                    CommandExample ("less +G file", "Open positioned at the end"),
                    CommandExample ("less -N file", "Show line numbers"),
                    CommandExample ("journalctl -u nginx | less", "Page the output of another command"),
                ]),

            CommandEntry (
                command: "head -n 50 file",
                summary: "First 50 lines",
                detail: """
                Prints the beginning of a file — useful for peeking at the shape of a large CSV or \
                checking a header without loading the whole thing. **-n** sets the count; the default \
                is 10.
                """,
                examples: [
                    CommandExample ("head file.csv", "First 10 lines"),
                    CommandExample ("head -n 50 file", "First 50 lines"),
                    CommandExample ("head -c 200 file", "First 200 bytes, regardless of lines"),
                ]),

            CommandEntry (
                command: "tail -f file",
                summary: "Follow a file as it grows — the standard way to watch a log",
                detail: """
                `tail` prints the end of a file. **-f** (follow) then keeps the command running and \
                prints new lines as they are written, which is how you watch a log live while you \
                reproduce a problem. Press Ctrl-c to stop.

                Prefer **-F** on log files: it survives log rotation, where the original file is \
                renamed out from under you and plain `-f` would keep watching the old one forever.
                """,
                examples: [
                    CommandExample ("tail file", "Last 10 lines"),
                    CommandExample ("tail -n 100 file", "Last 100 lines"),
                    CommandExample ("tail -f /var/log/nginx/error.log", "Watch a log live"),
                    CommandExample ("tail -F /var/log/app.log", "Keep following across log rotation"),
                ]),

            CommandEntry (
                command: "wc -l file",
                summary: "Count lines",
                detail: """
                *Word count*, though it counts lines (**-l**), words (**-w**) and bytes (**-c**) too. \
                Most often it appears at the end of a pipeline to answer "how many?" without printing \
                everything.
                """,
                examples: [
                    CommandExample ("wc -l access.log", "How many lines in the log"),
                    CommandExample ("ls | wc -l", "How many entries in this directory"),
                    CommandExample ("grep -c ERROR app.log", "Counting matches — grep does it directly"),
                ]),
        ]),

    CommandCategory (
        name: "Searching",
        icon: "magnifyingglass",
        intro: """
        Two different jobs that are easy to confuse: `grep` searches *inside* files for text, while \
        `find` searches *for* files by their name, size or age.
        """,
        entries: [
            CommandEntry (
                command: "grep -rn \"text\" .",
                summary: "Search recursively, showing line numbers",
                detail: """
                Searches file contents for a pattern. **-r** recurses through a directory, **-n** \
                prints the line number of each match so you can jump straight there. This combination \
                is the workhorse for "where is this string used?"

                The pattern is a regular expression, so characters like `.` `*` `[` have special \
                meaning. Use **-F** to search for a literal string instead.
                """,
                examples: [
                    CommandExample ("grep -rn \"api_key\" .", "Find a string anywhere below here, with line numbers"),
                    CommandExample ("grep -rn --include=\"*.py\" \"def main\" .", "Restrict the search to Python files"),
                    CommandExample ("grep -A 3 -B 3 ERROR app.log", "Show 3 lines of context after and before each match"),
                    CommandExample ("grep -F \"1.2.3\" file", "Treat the pattern literally, not as a regex"),
                ]),

            CommandEntry (
                command: "grep -i \"text\" file",
                summary: "Case-insensitive search",
                detail: """
                **-i** ignores case, so `error` also matches `Error` and `ERROR`. Worth making a \
                reflex when searching logs, since applications are wildly inconsistent about how they \
                capitalise their messages.
                """,
                examples: [
                    CommandExample ("grep -i error app.log", "Match error, Error and ERROR"),
                    CommandExample ("grep -iw cat file", "-w matches whole words only, so not \"category\""),
                ]),

            CommandEntry (
                command: "grep -v \"text\" file",
                summary: "Show lines that do *not* match",
                detail: """
                **-v** inverts the match. Its main use is subtraction: filtering out the noise you \
                already know about so that what remains is the part you have not explained yet. \
                Several `grep -v` stages can be chained with pipes.
                """,
                examples: [
                    CommandExample ("grep -v \"^#\" config.conf", "Hide comment lines"),
                    CommandExample ("grep -v \"^$\" file", "Hide blank lines"),
                    CommandExample ("ps aux | grep nginx | grep -v grep", "List nginx processes without matching the grep itself"),
                ]),

            CommandEntry (
                command: "find . -name \"*.log\"",
                summary: "Find files by name",
                detail: """
                Walks a directory tree and prints paths matching your criteria. The first argument is \
                where to start; everything after that is a test. Quote the pattern — otherwise the \
                shell expands `*.log` before `find` ever sees it, and you get the wrong results in a \
                way that is hard to spot.
                """,
                examples: [
                    CommandExample ("find . -name \"*.log\"", "Every .log file below here"),
                    CommandExample ("find . -iname \"readme*\"", "Case-insensitive name match"),
                    CommandExample ("find . -type d -name node_modules", "Only directories with that name"),
                    CommandExample ("find /etc -name \"*.conf\" 2>/dev/null", "Discard the permission-denied noise"),
                ]),

            CommandEntry (
                command: "find . -mtime -1",
                summary: "Files modified in the last day",
                detail: """
                **-mtime** filters by modification time in days: `-1` means less than one day ago, \
                `+7` means more than seven days ago. Use **-mmin** for minutes. This answers "what \
                changed recently?", which is often the fastest route to the cause of a new problem.
                """,
                examples: [
                    CommandExample ("find . -mtime -1", "Changed in the last 24 hours"),
                    CommandExample ("find . -mmin -30", "Changed in the last 30 minutes"),
                    CommandExample ("find /var/log -mtime +30 -name \"*.gz\"", "Old rotated logs, candidates for deletion"),
                ]),

            CommandEntry (
                command: "find . -size +100M",
                summary: "Files larger than 100 MB",
                detail: """
                Filters by size, where `+` means larger and `-` means smaller. Combined with `ls -lh` \
                through **-exec**, this is how you track down what filled a disk when the offender is \
                one big file rather than many small ones.
                """,
                examples: [
                    CommandExample ("find . -size +100M", "Files over 100 MB"),
                    CommandExample ("find . -size +1G -exec ls -lh {} +", "Find them and show their details"),
                    CommandExample ("find . -empty -type f", "Zero-length files"),
                ],
                caution: """
                **-exec** runs a command on every result. Read the command twice before using it with \
                `rm` — a mistyped test can match far more than you intended.
                """),

            CommandEntry (
                command: "which command",
                summary: "Show which binary a name resolves to",
                detail: """
                Searches your `PATH` and prints the executable that would actually run. Invaluable \
                when a command behaves unexpectedly — you may be running a different version than you \
                think, from a different directory. `type` is the more thorough shell builtin, since \
                it also reveals aliases and functions.
                """,
                examples: [
                    CommandExample ("which python3", "The path to the binary that would run"),
                    CommandExample ("type ls", "Reveals aliases and shell builtins that `which` misses"),
                    CommandExample ("command -v docker", "Portable existence check, handy in scripts"),
                ]),
        ]),

    CommandCategory (
        name: "Text Processing",
        icon: "text.alignleft",
        intro: """
        The classic Unix idea: small tools that read text on standard input and write text on \
        standard output, joined with pipes into something bigger than any one of them.
        """,
        entries: [
            CommandEntry (
                command: "sed -i 's/old/new/g' file",
                summary: "Replace text in place throughout a file",
                detail: """
                *Stream editor*. The `s/old/new/g` expression means substitute `old` with `new`, and \
                the trailing **g** makes it apply to every occurrence on a line rather than only the \
                first. **-i** edits the file in place instead of printing the result.

                On macOS, **-i** requires an argument for the backup suffix, so the portable form is \
                `sed -i '' 's/old/new/g' file` — a difference that catches people out constantly.
                """,
                examples: [
                    CommandExample ("sed 's/old/new/g' file", "Print the result without changing the file"),
                    CommandExample ("sed -i.bak 's/old/new/g' file", "Edit in place, keeping file.bak as a backup"),
                    CommandExample ("sed -n '10,20p' file", "Print only lines 10 to 20"),
                    CommandExample ("sed '/^#/d' config", "Delete comment lines from the output"),
                ],
                caution: "Run it without **-i** first and read the output. In-place editing has no undo."),

            CommandEntry (
                command: "awk '{print $2}' file",
                summary: "Print the second whitespace-separated field",
                detail: """
                A small programming language for column-shaped text. It splits each line into fields \
                — `$1`, `$2` and so on, with `$0` being the whole line — and runs your program on \
                each. For pulling one column out of command output it is unbeatable.
                """,
                examples: [
                    CommandExample ("awk '{print $2}' file", "The second column of every line"),
                    CommandExample ("ps aux | awk '{print $2, $11}'", "Just the PID and the command name"),
                    CommandExample ("awk -F: '{print $1}' /etc/passwd", "-F sets the separator; here, colon"),
                    CommandExample ("awk '$3 > 100 {print $1}' data", "Only lines where column 3 exceeds 100"),
                ]),

            CommandEntry (
                command: "sort file | uniq -c",
                summary: "Count how often each line occurs",
                detail: """
                `uniq` only collapses runs of *adjacent* identical lines, so it is nearly always \
                preceded by `sort`. With **-c** it prefixes each line with its count. Adding \
                `sort -rn` afterwards ranks them, giving you a frequency table — the standard way to \
                find the noisiest error or the busiest IP address in a log.
                """,
                examples: [
                    CommandExample ("sort file | uniq", "Remove duplicate lines"),
                    CommandExample ("sort file | uniq -c | sort -rn | head", "Top 10 most frequent lines"),
                    CommandExample ("sort -u file", "Sort and deduplicate in one step"),
                    CommandExample ("sort -h file", "Sort human-readable sizes like 4.0K and 2.3G correctly"),
                ]),

            CommandEntry (
                command: "cut -d: -f1 /etc/passwd",
                summary: "Take a field from delimited text",
                detail: """
                A simpler `awk` for the common case: **-d** sets the delimiter and **-f** picks the \
                field. Note that `cut` treats each delimiter as significant, so runs of spaces \
                produce empty fields — for whitespace-separated columns, `awk` is the better choice.
                """,
                examples: [
                    CommandExample ("cut -d: -f1 /etc/passwd", "Every username on the system"),
                    CommandExample ("cut -d, -f1,3 data.csv", "Columns 1 and 3 of a CSV"),
                    CommandExample ("cut -c1-10 file", "The first 10 characters of each line"),
                ]),

            CommandEntry (
                command: "tr -d '\\r' < in > out",
                summary: "Strip carriage returns from a Windows file",
                detail: """
                *Translate*: substitutes or deletes characters. Its most common use in practice is \
                fixing line endings — a file created on Windows ends its lines with carriage return \
                plus newline, and the stray carriage returns make shell scripts fail with baffling \
                errors.
                """,
                examples: [
                    CommandExample ("tr -d '\\r' < win.sh > unix.sh", "Convert Windows line endings to Unix"),
                    CommandExample ("tr 'A-Z' 'a-z' < file", "Convert to lowercase"),
                    CommandExample ("tr -s ' ' < file", "Squeeze repeated spaces into one"),
                ],
                caution: """
                If a script fails with an error mentioning `^M` or an unexpected character, stray \
                carriage returns are almost always the cause.
                """),

            CommandEntry (
                command: "diff -u a b",
                summary: "Compare two files, unified format",
                detail: """
                Shows what would have to change to turn the first file into the second. **-u** \
                produces the unified format familiar from patches and code review: lines prefixed \
                with `-` are in the first file, `+` in the second. Silence means the files are \
                identical.
                """,
                examples: [
                    CommandExample ("diff -u old.conf new.conf", "See what changed between two configs"),
                    CommandExample ("diff -r dir1 dir2", "Compare two directory trees"),
                    CommandExample ("diff <(ls dir1) <(ls dir2)", "Compare the output of two commands directly"),
                ]),
        ]),

    CommandCategory (
        name: "Processes",
        icon: "gauge",
        intro: """
        Every running program is a process with a numeric ID (a PID). These commands show you what is \
        running, what it is consuming, and how to stop it.
        """,
        entries: [
            CommandEntry (
                command: "ps aux",
                summary: "List every running process",
                detail: """
                A snapshot of everything running. The odd flag cluster is historical: **a** means all \
                users, **u** gives the detailed user-oriented format, and **x** includes processes \
                with no controlling terminal — which is most background services. Column 2 is the PID \
                you will pass to `kill`.
                """,
                examples: [
                    CommandExample ("ps aux", "Everything running, in detail"),
                    CommandExample ("ps aux --sort=-%mem | head", "The ten biggest memory consumers"),
                    CommandExample ("ps -ef --forest", "Show the parent/child tree"),
                    CommandExample ("pgrep -a nginx", "A cleaner way to find processes by name"),
                ]),

            CommandEntry (
                command: "ps aux | grep name",
                summary: "Find a process by name",
                detail: """
                The everyday idiom for "is this thing running, and what is its PID?" Note that the \
                `grep` will usually match itself, producing one confusing extra line; \
                `grep -v grep` removes it, and `pgrep` avoids the problem entirely.
                """,
                examples: [
                    CommandExample ("ps aux | grep nginx", "Find nginx processes"),
                    CommandExample ("ps aux | grep [n]ginx", "The bracket trick stops grep matching itself"),
                    CommandExample ("pgrep -a nginx", "The purpose-built tool for this"),
                ]),

            CommandEntry (
                command: "top",
                summary: "Live process and CPU view; q to quit",
                detail: """
                Refreshes continuously, sorted by CPU by default. Inside it, **M** sorts by memory, \
                **P** by CPU, **k** kills a process and **q** quits. The load average in the header \
                is the number of processes wanting to run — compare it against your core count, since \
                a load of 4 is healthy on 8 cores and dire on one.
                """,
                examples: [
                    CommandExample ("top", "Live view of the busiest processes"),
                    CommandExample ("top -u www-data", "Only one user's processes"),
                    CommandExample ("top -b -n 1 > snapshot.txt", "Batch mode: capture one snapshot to a file"),
                ]),

            CommandEntry (
                command: "htop",
                summary: "Friendlier top, if installed",
                detail: """
                The same job as `top` with colour, per-core meters, mouse support and painless \
                scrolling. Not installed by default on most systems, but usually one \
                `apt install htop` away and worth it if you spend time on the machine.
                """,
                examples: [
                    CommandExample ("htop", "Interactive process viewer"),
                    CommandExample ("htop -u postgres", "Filter to one user"),
                ]),

            CommandEntry (
                command: "kill PID",
                summary: "Ask a process to exit",
                detail: """
                Despite the name, plain `kill` politely *asks*: it sends SIGTERM, which a well-behaved \
                program handles by finishing its work, flushing its buffers and exiting cleanly. \
                Always try this first — give it a few seconds before escalating.
                """,
                examples: [
                    CommandExample ("kill 1234", "Ask process 1234 to shut down"),
                    CommandExample ("kill -HUP 1234", "Many daemons reload their config on SIGHUP"),
                    CommandExample ("kill -l", "List the available signals"),
                ]),

            CommandEntry (
                command: "kill -9 PID",
                summary: "Force a process to die — last resort",
                detail: """
                Signal 9 is SIGKILL, which the process cannot catch or ignore; the kernel simply stops \
                it. That is why it always works, and also why it is a last resort: the program gets no \
                chance to flush buffers, finish a write, or remove its lock files, so it can leave \
                corrupt data or a stale lock behind.
                """,
                examples: [
                    CommandExample ("kill -9 1234", "Force process 1234 to die immediately"),
                    CommandExample ("kill 1234", "Try this first, and wait a few seconds"),
                ],
                caution: """
                Never make `kill -9` your first move on a database or anything mid-write. Try plain \
                `kill` and give it time.
                """),

            CommandEntry (
                command: "pkill -f pattern",
                summary: "Kill by matching the full command line",
                detail: """
                Kills by name rather than PID. **-f** matches against the entire command line, not \
                just the program name, which is what you need for things like \
                `python worker.py --queue emails` where every process shares the name `python`.
                """,
                examples: [
                    CommandExample ("pkill nginx", "Kill processes named nginx"),
                    CommandExample ("pkill -f \"worker.py --queue emails\"", "Match the full command line"),
                    CommandExample ("pgrep -af \"worker.py\"", "Always preview the matches first"),
                ],
                caution: """
                A loose pattern can match far more than you meant. Run the same pattern through \
                `pgrep -af` first and read the list before you kill it.
                """),

            CommandEntry (
                command: "free -h",
                summary: "Memory in use and available",
                detail: """
                Read the **available** column, not **free**. Linux deliberately uses spare memory as \
                disk cache, so `free` is usually near zero on a healthy machine and that is fine — \
                the cache is handed back the moment a program needs it. Real memory pressure shows up \
                as low *available* plus active swap.
                """,
                examples: [
                    CommandExample ("free -h", "Human-readable memory summary"),
                    CommandExample ("free -h -s 5", "Refresh every 5 seconds"),
                    CommandExample ("swapon --show", "Whether swap exists and how much is in use"),
                ]),

            CommandEntry (
                command: "uptime",
                summary: "How long the machine has been up, and load average",
                detail: """
                Gives the time since boot plus three load averages — over one, five and fifteen \
                minutes. The shape matters more than the numbers: rising means the problem is \
                building, falling means the worst has passed.
                """,
                examples: [
                    CommandExample ("uptime", "Uptime and the three load averages"),
                    CommandExample ("nproc", "Core count, so you know what load is actually high"),
                    CommandExample ("who", "Who else is logged in right now"),
                ]),
        ]),

    CommandCategory (
        name: "Networking",
        icon: "network",
        intro: """
        When something cannot connect, work outward: does the address resolve, does the port answer, \
        and is anything actually listening on the other end?
        """,
        entries: [
            CommandEntry (
                command: "ip a",
                summary: "Show network interfaces and addresses",
                detail: """
                Short for `ip address`. Lists every interface and the addresses assigned to it. \
                `lo` is loopback (127.0.0.1) and always present; the interface with your real address \
                is usually `eth0`, `ens3` or similar. Replaces the older `ifconfig`, which is absent \
                from many modern distributions.
                """,
                examples: [
                    CommandExample ("ip a", "All interfaces and addresses"),
                    CommandExample ("ip -4 a", "IPv4 only, which is usually what you want"),
                    CommandExample ("ip route", "The routing table, including the default gateway"),
                    CommandExample ("hostname -I", "Just the addresses, nothing else"),
                ]),

            CommandEntry (
                command: "ss -tulpn",
                summary: "Which ports are listening, and what owns them",
                detail: """
                The single most useful network diagnostic. The flags: **-t** TCP, **-u** UDP, **-l** \
                listening only, **-p** show the owning process, **-n** numeric ports instead of \
                service names. Run it when a connection is refused — if nothing is listening, the \
                problem is the service, not the network.

                Watch the address: something bound to `127.0.0.1:5432` accepts only local \
                connections, while `0.0.0.0:5432` accepts them from anywhere. That distinction \
                explains a great many "it works on the server but not from outside" puzzles.
                """,
                examples: [
                    CommandExample ("ss -tulpn", "Every listening TCP and UDP port with its process"),
                    CommandExample ("sudo ss -tulpn", "Needs root to show processes you do not own"),
                    CommandExample ("ss -tan state established", "Current established connections"),
                    CommandExample ("netstat -tulpn", "The older equivalent, on systems without ss"),
                ]),

            CommandEntry (
                command: "ping -c 4 host",
                summary: "Send four pings",
                detail: """
                Tests basic reachability. **-c** limits the count, without which it runs until you \
                press Ctrl-c. A reply proves the host is up and routable, but silence does not prove \
                the opposite: plenty of firewalls and cloud providers drop ICMP by default while \
                happily serving traffic on real ports.
                """,
                examples: [
                    CommandExample ("ping -c 4 example.com", "Four pings and a summary"),
                    CommandExample ("ping -c 4 8.8.8.8", "Ping an IP to separate DNS problems from routing"),
                    CommandExample ("traceroute example.com", "Show every hop along the path"),
                ]),

            CommandEntry (
                command: "curl -I https://example.com",
                summary: "Fetch just the response headers",
                detail: """
                **-I** issues a HEAD request, so you get the status line and headers without the \
                body. It is the quickest way to check whether a service is up, what it redirects to, \
                and what it claims about caching — all without filling your terminal with HTML.
                """,
                examples: [
                    CommandExample ("curl -I https://example.com", "Status and headers only"),
                    CommandExample ("curl -sS https://api.example.com/health", "Quiet, but still show errors"),
                    CommandExample ("curl -L http://example.com", "Follow redirects to the final destination"),
                    CommandExample ("curl -v https://example.com", "Verbose: the full TLS and request handshake"),
                ]),

            CommandEntry (
                command: "curl -O https://example.com/f",
                summary: "Download a file",
                detail: """
                **-O** (capital letter O) saves the file under its remote name; **-o** (lowercase) \
                lets you choose the name yourself. `wget` does the same job with a friendlier default \
                and better resume behaviour, if it is installed.
                """,
                examples: [
                    CommandExample ("curl -O https://example.com/archive.tar.gz", "Save with the remote filename"),
                    CommandExample ("curl -o local.tar.gz https://example.com/f", "Save under a name you choose"),
                    CommandExample ("wget -c https://example.com/big.iso", "Resume an interrupted download"),
                ]),

            CommandEntry (
                command: "dig +short example.com",
                summary: "Resolve a name, terse output",
                detail: """
                Queries DNS. **+short** strips everything down to the answer itself. When a service \
                is unreachable, checking resolution first splits the problem cleanly in two: a name \
                that does not resolve is a DNS issue, while a name that resolves to an unexpected \
                address points at stale records or split-horizon DNS.
                """,
                examples: [
                    CommandExample ("dig +short example.com", "Just the IP address"),
                    CommandExample ("dig example.com MX", "Mail server records"),
                    CommandExample ("dig @8.8.8.8 example.com", "Ask a specific resolver, bypassing the local one"),
                    CommandExample ("getent hosts example.com", "Resolve the way the system itself would"),
                ]),

            CommandEntry (
                command: "scp file user@host:/path",
                summary: "Copy a file to another machine over SSH",
                detail: """
                Copies over an SSH connection, using the same keys and config as `ssh` itself. The \
                colon is what makes a path remote — omit it and you have simply made a local copy \
                with a strange name, which is a classic mistake.
                """,
                examples: [
                    CommandExample ("scp file.txt user@host:/tmp/", "Local file to a remote directory"),
                    CommandExample ("scp user@host:/var/log/app.log .", "Remote file down to here"),
                    CommandExample ("scp -r dir/ user@host:/opt/", "A whole directory"),
                    CommandExample ("scp -P 2222 file user@host:/tmp/", "Non-standard port; note the capital P"),
                ],
                caution: """
                Inside a session in this app you can skip `scp` altogether — the folder button opens \
                an SFTP browser on the same connection.
                """),

            CommandEntry (
                command: "rsync -avz src/ user@host:dst/",
                summary: "Sync directories efficiently",
                detail: """
                Copies only the differences, which makes it dramatically faster than `scp` for \
                repeated transfers and safe to re-run after an interruption. The flags: **-a** \
                archive mode (recursive, preserving permissions and times), **-v** verbose, **-z** \
                compress in transit.

                The trailing slash on the source is significant. `src/` copies the *contents* of src \
                into dst; `src` copies the directory itself, creating `dst/src`.
                """,
                examples: [
                    CommandExample ("rsync -avz src/ user@host:/backup/", "Sync contents to a remote directory"),
                    CommandExample ("rsync -avzn src/ user@host:/backup/", "-n is a dry run: shows what would happen"),
                    CommandExample ("rsync -avz --delete src/ dst/", "Make dst match src exactly, removing extras"),
                ],
                caution: """
                **--delete** removes files from the destination that are gone from the source. Always \
                run it once with **-n** first.
                """),
        ]),

    CommandCategory (
        name: "Permissions and Users",
        icon: "lock",
        intro: """
        Every file has an owner, a group, and three sets of permissions — read (4), write (2) and \
        execute (1) — for the owner, the group, and everyone else. The numeric modes are just those \
        values added together.
        """,
        entries: [
            CommandEntry (
                command: "chmod 644 file",
                summary: "Owner read/write, everyone else read",
                detail: """
                Each digit is one set of permissions, added from read 4, write 2 and execute 1. So \
                `644` is 6 (4+2, read and write) for the owner and 4 (read) for group and others — \
                the normal mode for an ordinary file.
                """,
                examples: [
                    CommandExample ("chmod 644 file.txt", "The standard mode for a regular file"),
                    CommandExample ("chmod 600 secret.key", "Owner only — required for SSH private keys"),
                    CommandExample ("chmod u+x script.sh", "Symbolic form: add execute for the owner"),
                    CommandExample ("chmod -R 755 /var/www", "Apply recursively to a whole tree"),
                ]),

            CommandEntry (
                command: "chmod 755 script.sh",
                summary: "Make a script executable",
                detail: """
                `755` gives the owner read, write and execute, and everyone else read and execute. \
                A script needs the execute bit before you can run it as `./script.sh` — without it \
                you get "Permission denied" even though the file is plainly readable.
                """,
                examples: [
                    CommandExample ("chmod 755 script.sh", "Executable by everyone, writable only by you"),
                    CommandExample ("chmod +x script.sh", "The quick form: add execute for all"),
                    CommandExample ("./script.sh", "Run it — the ./ is required for the current directory"),
                ]),

            CommandEntry (
                command: "chown user:group file",
                summary: "Change owner and group",
                detail: """
                Sets who owns a file. Almost always needs `sudo`, since giving away a file you own is \
                restricted. The group half is optional — `chown user file` changes only the owner.
                """,
                examples: [
                    CommandExample ("sudo chown www-data:www-data /var/www/site", "Hand a directory to the web server"),
                    CommandExample ("sudo chown -R $USER:$USER ~/project", "Take ownership of a whole tree"),
                    CommandExample ("stat -c '%U %G %a' file", "Check the current owner, group and mode"),
                ]),

            CommandEntry (
                command: "sudo command",
                summary: "Run one command as root",
                detail: """
                Runs a single command with elevated privileges, prompting for *your* password rather \
                than root's, and logging what was run. Preferring `sudo` over a permanent root shell \
                keeps that audit trail and limits how much of your session runs with the power to \
                destroy the system.
                """,
                examples: [
                    CommandExample ("sudo systemctl restart nginx", "Restart a service"),
                    CommandExample ("sudo !!", "Repeat the previous command with sudo"),
                    CommandExample ("sudo -u postgres psql", "Run as a specific user, not root"),
                ],
                caution: """
                Redirection happens as *you*, not as root, so `sudo echo x > /etc/file` still fails. \
                Use `echo x | sudo tee /etc/file` instead.
                """),

            CommandEntry (
                command: "sudo -i",
                summary: "Open a root shell",
                detail: """
                Starts an interactive login shell as root, with root's environment. Convenient during \
                a long maintenance session, but everything you type afterwards runs unprotected, and \
                the individual commands are less clearly attributed in the logs. Leave with `exit`.
                """,
                examples: [
                    CommandExample ("sudo -i", "Root login shell"),
                    CommandExample ("sudo -s", "Root shell keeping your current environment"),
                    CommandExample ("exit", "Return to your own user"),
                ],
                caution: "Every safety net is off in a root shell. Prefer `sudo` per command where you can."),

            CommandEntry (
                command: "id",
                summary: "Show your user and group membership",
                detail: """
                Prints your user ID, primary group and every supplementary group. When you have been \
                added to a group but still get permission denied, this is how you confirm it — group \
                membership is only picked up at login, so you usually need to log out and back in.
                """,
                examples: [
                    CommandExample ("id", "Your own user and groups"),
                    CommandExample ("id someuser", "Another user's groups"),
                    CommandExample ("groups", "Just the group names"),
                    CommandExample ("whoami", "Just the username — useful after sudo"),
                ]),

            CommandEntry (
                command: "passwd",
                summary: "Change your password",
                detail: """
                Changes your own password, asking for the current one first. With a username \
                argument and `sudo`, an administrator can change someone else's without knowing it.
                """,
                examples: [
                    CommandExample ("passwd", "Change your own password"),
                    CommandExample ("sudo passwd someuser", "Change another user's password"),
                    CommandExample ("sudo passwd -l someuser", "Lock an account's password login"),
                ]),
        ]),

    CommandCategory (
        name: "Services and Logs",
        icon: "server.rack",
        intro: """
        On modern Linux, `systemd` starts and supervises background services, and `journalctl` reads \
        the log it collects from them. When a service misbehaves, `status` then `journalctl` answers \
        most questions.
        """,
        entries: [
            CommandEntry (
                command: "systemctl status name",
                summary: "Is this service running, and why not",
                detail: """
                The first command to run when something is not working. It shows whether the service \
                is active, whether it is enabled at boot, its main PID, and — most usefully — the \
                last few log lines, which usually contain the actual error.

                *Active* means running now; *enabled* means it will start at boot. These are \
                independent, and a service that is active but not enabled will quietly vanish after \
                the next reboot.
                """,
                examples: [
                    CommandExample ("systemctl status nginx", "State, PID and recent log lines"),
                    CommandExample ("systemctl status nginx --no-pager -l", "Full output, not truncated or paged"),
                    CommandExample ("systemctl is-active nginx", "Just the state, for scripts"),
                    CommandExample ("systemctl list-units --failed", "Everything currently failed on the machine"),
                ]),

            CommandEntry (
                command: "systemctl restart name",
                summary: "Restart a service",
                detail: """
                Stops and starts the service. Prefer `reload` where the service supports it, since it \
                re-reads the configuration without dropping connections. `reload-or-restart` picks \
                whichever the unit supports.
                """,
                examples: [
                    CommandExample ("sudo systemctl restart nginx", "Full stop and start"),
                    CommandExample ("sudo systemctl reload nginx", "Re-read config without dropping connections"),
                    CommandExample ("sudo nginx -t", "Test the config *before* reloading it"),
                ],
                caution: """
                Validate the configuration before restarting. A service that fails to start on a bad \
                config leaves you with an outage instead of a warning.
                """),

            CommandEntry (
                command: "systemctl enable --now name",
                summary: "Start now and on every boot",
                detail: """
                `enable` arranges for the service to start at boot; **--now** also starts it \
                immediately, saving a second command. The inverse is `disable --now`.
                """,
                examples: [
                    CommandExample ("sudo systemctl enable --now nginx", "Start it and make it permanent"),
                    CommandExample ("sudo systemctl disable --now nginx", "Stop it and keep it stopped"),
                    CommandExample ("systemctl is-enabled nginx", "Will it come back after a reboot?"),
                ]),

            CommandEntry (
                command: "journalctl -u name -f",
                summary: "Follow one service's log live",
                detail: """
                `journalctl` reads systemd's collected logs. **-u** narrows to one unit and **-f** \
                follows new entries as they arrive, exactly like `tail -f`. Reproduce the problem \
                with this running and watch the error appear.
                """,
                examples: [
                    CommandExample ("journalctl -u nginx -f", "Follow one service live"),
                    CommandExample ("journalctl -u nginx -n 100", "The last 100 lines"),
                    CommandExample ("journalctl -u nginx --since \"10 min ago\"", "A time window, in plain language"),
                    CommandExample ("journalctl -u nginx --since today --no-pager", "Everything today, unpaged"),
                ]),

            CommandEntry (
                command: "journalctl -p err -b",
                summary: "Errors since the last boot",
                detail: """
                **-p err** filters by priority, keeping errors and worse, and **-b** limits to the \
                current boot. Together they are an excellent triage sweep on an unfamiliar machine: \
                a short list of everything that has actually gone wrong since it started.
                """,
                examples: [
                    CommandExample ("journalctl -p err -b", "Errors since boot"),
                    CommandExample ("journalctl -b -1", "Logs from the *previous* boot — why did it reboot?"),
                    CommandExample ("journalctl --disk-usage", "How much space the journal is consuming"),
                ]),

            CommandEntry (
                command: "dmesg | tail",
                summary: "Recent kernel messages",
                detail: """
                The kernel's own ring buffer: hardware detection, disk errors, filesystem problems \
                and the out-of-memory killer's decisions. When a process dies with no explanation in \
                the application log, `dmesg` is where you find out the kernel killed it.
                """,
                examples: [
                    CommandExample ("dmesg | tail", "The most recent kernel messages"),
                    CommandExample ("dmesg -T | tail -50", "-T prints human-readable timestamps"),
                    CommandExample ("dmesg | grep -i 'out of memory'", "Was the process OOM-killed?"),
                ]),
        ]),

    CommandCategory (
        name: "Packages",
        icon: "shippingbox",
        intro: """
        Which package manager you use depends on the distribution, but the operations map onto each \
        other closely: refresh the index, install, remove, search.
        """,
        entries: [
            CommandEntry (
                command: "apt update && apt upgrade",
                summary: "Debian/Ubuntu: refresh and install updates",
                detail: """
                Two distinct steps, which is why they are chained. `update` refreshes the local list \
                of what is available — it installs nothing. `upgrade` then installs newer versions of \
                what you already have. Running `upgrade` without `update` first is the usual reason \
                someone finds "no updates" on a machine that is months behind.
                """,
                examples: [
                    CommandExample ("sudo apt update && sudo apt upgrade", "The standard update cycle"),
                    CommandExample ("sudo apt upgrade -y", "Assume yes; only when you know what is coming"),
                    CommandExample ("apt list --upgradable", "See what would change first"),
                ]),

            CommandEntry (
                command: "apt install package",
                summary: "Debian/Ubuntu: install",
                detail: """
                Installs a package and its dependencies. Use `apt search` if you are unsure of the \
                exact name, and `apt show` to see what a package actually is before installing it.
                """,
                examples: [
                    CommandExample ("sudo apt install htop", "Install a package"),
                    CommandExample ("apt search json", "Search for packages"),
                    CommandExample ("apt show nginx", "Description, size and dependencies"),
                    CommandExample ("sudo apt remove --purge nginx", "Remove it along with its config files"),
                ]),

            CommandEntry (
                command: "dnf install package",
                summary: "Fedora/RHEL: install",
                detail: """
                The Fedora, RHEL, Rocky and Alma equivalent of `apt`. On older RHEL and CentOS \
                systems the command is `yum`, with the same syntax.
                """,
                examples: [
                    CommandExample ("sudo dnf install htop", "Install a package"),
                    CommandExample ("sudo dnf update", "Refresh and upgrade in one step, unlike apt"),
                    CommandExample ("dnf search json", "Search for packages"),
                ]),

            CommandEntry (
                command: "apk add package",
                summary: "Alpine: install",
                detail: """
                Alpine Linux's package manager, which you meet most often inside Docker containers, \
                since Alpine images are small. **--no-cache** avoids leaving the package index behind \
                in an image layer.
                """,
                examples: [
                    CommandExample ("apk add curl", "Install a package"),
                    CommandExample ("apk add --no-cache curl", "Install without caching the index"),
                    CommandExample ("apk del curl", "Remove a package"),
                ]),

            CommandEntry (
                command: "brew install package",
                summary: "macOS: install with Homebrew",
                detail: """
                The de facto package manager for macOS. Notably it does *not* want `sudo` — Homebrew \
                installs into a directory you own, and using sudo with it causes permission problems \
                that are tedious to unpick.
                """,
                examples: [
                    CommandExample ("brew install wget", "Install a command-line tool"),
                    CommandExample ("brew search wget", "Search for a formula"),
                    CommandExample ("brew upgrade", "Upgrade everything installed"),
                ],
                caution: "Do not run `brew` with `sudo`."),
        ]),

    CommandCategory (
        name: "Archives",
        icon: "doc.zipper",
        intro: """
        `tar` bundles many files into one; gzip and friends compress. The two jobs are separate, \
        which is why a compressed tarball has two extensions.
        """,
        entries: [
            CommandEntry (
                command: "tar -czf out.tar.gz dir",
                summary: "Create a gzipped tarball",
                detail: """
                Read the flags as a sentence: **c** create, **z** gzip, **f** the filename that \
                follows. The output name comes immediately after **f**, then the things to include. \
                Extraction swaps **c** for **x**, and listing uses **t**.
                """,
                examples: [
                    CommandExample ("tar -czf backup.tar.gz mydir", "Create a compressed archive"),
                    CommandExample ("tar -czf backup.tar.gz -C /var/www site", "-C changes directory first, avoiding long paths inside"),
                    CommandExample ("tar -cJf backup.tar.xz mydir", "xz compression: slower, noticeably smaller"),
                ]),

            CommandEntry (
                command: "tar -xzf in.tar.gz",
                summary: "Extract a gzipped tarball",
                detail: """
                **x** extracts. Modern `tar` detects the compression automatically, so `tar -xf` \
                usually works whatever the format. Extraction goes into the current directory, so \
                list the contents first unless you are confident the archive contains a single \
                top-level folder.
                """,
                examples: [
                    CommandExample ("tar -xzf archive.tar.gz", "Extract here"),
                    CommandExample ("tar -xzf archive.tar.gz -C /opt/", "Extract somewhere specific"),
                    CommandExample ("tar -xzf archive.tar.gz path/to/one/file", "Extract a single file from the archive"),
                ],
                caution: """
                An archive built without a top-level directory scatters its contents across your \
                current directory. Check with `tar -tzf` first.
                """),

            CommandEntry (
                command: "tar -tzf in.tar.gz",
                summary: "List contents without extracting",
                detail: """
                **t** lists. Always worth running before extracting an archive you did not create, \
                both to see whether it has a containing folder and to check for absolute paths.
                """,
                examples: [
                    CommandExample ("tar -tzf archive.tar.gz", "List everything inside"),
                    CommandExample ("tar -tzf archive.tar.gz | head", "Just the first few entries"),
                ]),

            CommandEntry (
                command: "zip -r out.zip dir",
                summary: "Create a zip archive",
                detail: """
                Less common on Unix than tar, but the right choice when the recipient is on Windows \
                or macOS, where zip opens with a double-click. **-r** is required for directories.
                """,
                examples: [
                    CommandExample ("zip -r site.zip site/", "Zip a directory"),
                    CommandExample ("zip -r site.zip site/ -x \"*.log\"", "Exclude a pattern"),
                ]),

            CommandEntry (
                command: "unzip in.zip",
                summary: "Extract a zip archive",
                detail: """
                Extracts into the current directory. **-l** lists without extracting and **-d** \
                chooses a destination. Not always installed on minimal servers — `apt install unzip` \
                if it is missing.
                """,
                examples: [
                    CommandExample ("unzip archive.zip", "Extract here"),
                    CommandExample ("unzip -l archive.zip", "List the contents first"),
                    CommandExample ("unzip archive.zip -d /opt/app", "Extract to a specific directory"),
                ]),
        ]),

    CommandCategory (
        name: "Shell Tricks",
        icon: "wand.and.stars",
        intro: """
        Features of the shell itself rather than separate programs. These are the things that \
        separate slow typing from fluent use.
        """,
        entries: [
            CommandEntry (
                command: "!!",
                summary: "Repeat the previous command",
                detail: """
                Expands to the whole of your last command line. On its own it just re-runs it; its \
                real value is as a building block, most famously in `sudo !!` after a command fails \
                on permissions.
                """,
                examples: [
                    CommandExample ("!!", "Run the last command again"),
                    CommandExample ("sudo !!", "Run it again as root"),
                    CommandExample ("!$", "The *last argument* of the previous command"),
                    CommandExample ("!ssh", "The most recent command starting with ssh"),
                ]),

            CommandEntry (
                command: "sudo !!",
                summary: "Repeat the previous command as root",
                detail: """
                The fix for the most common mistake on a Unix system: running something that needed \
                privileges without them. Rather than retyping, this re-runs the exact line with sudo \
                in front.
                """,
                examples: [
                    CommandExample ("sudo !!", "Re-run the failed command with privileges"),
                ],
                caution: "It re-runs the line verbatim, as root. Be sure the previous command is what you think."),

            CommandEntry (
                command: "history | grep text",
                summary: "Find something you ran earlier",
                detail: """
                `history` prints your past commands, numbered. Piping it into `grep` finds that long \
                invocation from last week without reconstructing it. `!123` then re-runs entry 123 \
                directly. Interactive Ctrl-r search is usually faster still.
                """,
                examples: [
                    CommandExample ("history | grep rsync", "Find previous rsync commands"),
                    CommandExample ("history | tail -20", "The last 20 things you ran"),
                    CommandExample ("!123", "Re-run history entry number 123"),
                ],
                caution: """
                History files are plain text. A password typed on a command line stays in \
                `~/.bash_history` until you remove it.
                """),

            CommandEntry (
                command: "command &",
                summary: "Run in the background",
                detail: """
                A trailing `&` starts the command in the background and returns your prompt \
                immediately. The job is still tied to the shell, so it dies when you disconnect — \
                for anything that must outlive the session, use `nohup` or tmux.
                """,
                examples: [
                    CommandExample ("./long-task.sh &", "Start in the background"),
                    CommandExample ("jobs", "List background jobs from this shell"),
                    CommandExample ("fg", "Bring the most recent one back to the foreground"),
                    CommandExample ("bg", "Resume a Ctrl-z suspended job in the background"),
                ]),

            CommandEntry (
                command: "nohup command &",
                summary: "Keep running after you disconnect",
                detail: """
                `nohup` detaches the command from your session so it survives logout, writing its \
                output to `nohup.out` by default. On a mobile connection that drops without warning, \
                this matters — though tmux is the better answer, since it also lets you *reattach* \
                and see what happened.
                """,
                examples: [
                    CommandExample ("nohup ./migrate.sh &", "Survive a disconnect, output to nohup.out"),
                    CommandExample ("nohup ./migrate.sh > run.log 2>&1 &", "Send output somewhere you chose"),
                    CommandExample ("tmux new -s migrate", "Usually the better option: reattachable"),
                ]),

            CommandEntry (
                command: "command > out 2>&1",
                summary: "Send output and errors to a file",
                detail: """
                Programs write to two separate streams: standard output (1) and standard error (2). \
                `> out` redirects only the first, which is why errors still appear on screen. \
                `2>&1` then says "send stream 2 wherever stream 1 is going".

                The order matters: `> out 2>&1` works, but `2>&1 > out` does not, because the \
                duplication happens before the redirection.
                """,
                examples: [
                    CommandExample ("./script.sh > out.log 2>&1", "Capture everything in one file"),
                    CommandExample ("./script.sh >> out.log 2>&1", ">> appends instead of truncating"),
                    CommandExample ("./script.sh 2>/dev/null", "Discard errors, keep normal output"),
                    CommandExample ("./script.sh | tee out.log", "See it on screen *and* save it"),
                ],
                caution: "A single `>` truncates the target file immediately, before the command even runs."),

            CommandEntry (
                command: "export VAR=value",
                summary: "Set an environment variable for this session",
                detail: """
                Without `export` the variable exists only in the current shell; with it, the variable \
                is passed to every command you launch. It lasts until you log out — to make it \
                permanent, add the line to `~/.bashrc` or `~/.zshrc`.
                """,
                examples: [
                    CommandExample ("export PATH=$PATH:/opt/bin", "Add a directory to PATH"),
                    CommandExample ("export EDITOR=vim", "Set your preferred editor"),
                    CommandExample ("printenv", "List every environment variable"),
                    CommandExample ("VAR=value ./script.sh", "Set it for one command only"),
                ],
                caution: """
                Exported secrets are visible to every child process and often to `ps`. Prefer a file \
                with restrictive permissions for real credentials.
                """),

            CommandEntry (
                command: "Ctrl-c",
                summary: "Interrupt what is running",
                detail: """
                Sends SIGINT to the foreground program, asking it to stop. This is how you escape a \
                `tail -f`, a `ping`, or anything that is taking too long. Well-behaved programs clean \
                up before exiting.
                """,
                examples: [
                    CommandExample ("Ctrl-c", "Stop the running command"),
                    CommandExample ("Ctrl-z", "Suspend it instead, leaving it resumable"),
                ]),

            CommandEntry (
                command: "Ctrl-d",
                summary: "End of input, or log out",
                detail: """
                Signals end-of-input. At a shell prompt with nothing typed, that means "no more \
                commands" and logs you out — which is why it sometimes closes your session \
                unexpectedly. When a program is reading input, it marks the end of what you are \
                typing.
                """,
                examples: [
                    CommandExample ("Ctrl-d", "End input, or log out at an empty prompt"),
                    CommandExample ("exit", "The explicit way to leave a shell"),
                ]),

            CommandEntry (
                command: "Ctrl-r",
                summary: "Search backwards through your history",
                detail: """
                Starts an incremental search: type a few characters and the most recent matching \
                command appears. Press Ctrl-r again to step further back, **return** to run it, or \
                the arrow keys to edit it first. Far faster than pressing up repeatedly.
                """,
                examples: [
                    CommandExample ("Ctrl-r", "Start searching, then type part of the command"),
                    CommandExample ("Ctrl-r Ctrl-r", "Step to the next older match"),
                ]),

            CommandEntry (
                command: "Ctrl-z",
                summary: "Suspend to the background; fg to resume",
                detail: """
                Pauses the foreground program and returns your prompt. The job is stopped, not \
                killed: `fg` resumes it in the foreground and `bg` lets it continue in the \
                background. Useful for stepping out of an editor to check something, then returning.
                """,
                examples: [
                    CommandExample ("Ctrl-z", "Suspend the current program"),
                    CommandExample ("fg", "Resume it in the foreground"),
                    CommandExample ("bg", "Let it continue in the background"),
                    CommandExample ("jobs", "See what you have suspended"),
                ],
                caution: "Suspended jobs are easy to forget, and logging out may kill them."),
        ]),

    CommandCategory (
        name: "tmux",
        icon: "rectangle.split.3x1",
        intro: """
        tmux keeps your shell running on the *server*, independent of your connection. On a mobile \
        link that drops when you switch apps or lose signal, this is the difference between losing a \
        long-running job and reattaching to find it finished.

        Every binding starts with the prefix, Ctrl-b: press and release it, then press the next key.
        """,
        entries: [
            CommandEntry (
                command: "tmux new -s name",
                summary: "Start a named session",
                detail: """
                Creates a session and puts you inside it. Naming it with **-s** is what makes it easy \
                to reattach later — unnamed sessions get numbers, which are harder to tell apart once \
                you have several.
                """,
                examples: [
                    CommandExample ("tmux new -s deploy", "Start a named session"),
                    CommandExample ("tmux new -s deploy -d", "Create it detached, without entering it"),
                    CommandExample ("tmux new -As deploy", "Attach if it exists, otherwise create it"),
                ]),

            CommandEntry (
                command: "tmux attach -t name",
                summary: "Reattach after a disconnect",
                detail: """
                Reconnects you to a running session, with everything exactly as you left it. This is \
                the payoff: after a dropped connection, `ssh` back in, run this, and your work is \
                still there.
                """,
                examples: [
                    CommandExample ("tmux attach -t deploy", "Reattach to a named session"),
                    CommandExample ("tmux a", "Attach to the most recent session"),
                    CommandExample ("tmux attach -d -t deploy", "Detach any other client as you attach"),
                ],
                caution: """
                This app can do it for you: set a host's reconnect type to **tmux** and it attaches \
                automatically.
                """),

            CommandEntry (
                command: "tmux ls",
                summary: "List sessions",
                detail: """
                Shows every session on the machine with its window count and creation time. Run it \
                after logging back in to see what is still waiting for you.
                """,
                examples: [
                    CommandExample ("tmux ls", "List all sessions"),
                    CommandExample ("tmux kill-session -t deploy", "Remove one you are finished with"),
                ]),

            CommandEntry (
                command: "Ctrl-b d",
                summary: "Detach, leaving everything running",
                detail: """
                Detaches you from the session without stopping anything inside it. This is the \
                correct way to leave — typing `exit` would close the shell and lose the session.
                """,
                examples: [
                    CommandExample ("Ctrl-b d", "Detach and return to the normal shell"),
                    CommandExample ("tmux attach -t name", "Come back later"),
                ]),

            CommandEntry (
                command: "Ctrl-b c",
                summary: "New window",
                detail: """
                Creates another window in the session, like a tab. **Ctrl-b n** and **Ctrl-b p** move \
                between them, and **Ctrl-b** followed by a digit jumps straight to that number. \
                Windows suit separate tasks; panes suit things you want to watch side by side.
                """,
                examples: [
                    CommandExample ("Ctrl-b c", "Create a new window"),
                    CommandExample ("Ctrl-b n", "Next window"),
                    CommandExample ("Ctrl-b 2", "Jump to window 2"),
                    CommandExample ("Ctrl-b ,", "Rename the current window"),
                ]),

            CommandEntry (
                command: "Ctrl-b \"",
                summary: "Split horizontally (\" needs Shift)",
                detail: """
                Splits the current pane into two stacked halves, so you can run a command in one \
                while watching a log in the other. The quote character does need Shift — the prefix \
                itself does not.
                """,
                examples: [
                    CommandExample ("Ctrl-b \"", "Split into top and bottom panes"),
                    CommandExample ("Ctrl-b o", "Move to the next pane"),
                    CommandExample ("Ctrl-b z", "Zoom the current pane to full screen, and back"),
                ]),

            CommandEntry (
                command: "Ctrl-b %",
                summary: "Split vertically (% needs Shift)",
                detail: """
                Splits into two side-by-side panes. On a phone screen a vertical split leaves both \
                halves too narrow to be useful, so horizontal splits or separate windows usually work \
                better on mobile.
                """,
                examples: [
                    CommandExample ("Ctrl-b %", "Split into left and right panes"),
                    CommandExample ("Ctrl-b z", "Zoom one pane to full screen while you work in it"),
                ]),

            CommandEntry (
                command: "Ctrl-b o",
                summary: "Switch to the next pane",
                detail: """
                Cycles through the panes in the current window. The arrow keys after the prefix move \
                directionally, which is easier to think about once you have more than two.
                """,
                examples: [
                    CommandExample ("Ctrl-b o", "Cycle to the next pane"),
                    CommandExample ("Ctrl-b Left", "Move to the pane on the left"),
                    CommandExample ("Ctrl-b q", "Briefly show pane numbers"),
                ]),

            CommandEntry (
                command: "Ctrl-b x",
                summary: "Close the current pane",
                detail: """
                Closes the pane, asking for confirmation first. Typing `exit` in the pane does the \
                same thing. Closing the last pane in a window closes the window, and closing the last \
                window ends the session.
                """,
                examples: [
                    CommandExample ("Ctrl-b x", "Close this pane, with a confirmation prompt"),
                    CommandExample ("exit", "The same thing, typed"),
                ]),
        ]),
]
