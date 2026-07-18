# Project "Anchor" — iOS SSH Client: Architecture & MVP Spec
*Working title — rename freely. Version 0.1, 2026-07-16*

## 1. Strategy Recap

- **Phase 1 (Personal):** Working SSH client on your own iPhone/iPad, sideloaded via Xcode. Target: usable daily driver in 2–4 weekends with Claude Code.
- **Phase 2 (Commercial-optional):** Same codebase, App Store-ready. All dependencies MIT/Apache-2.0, so no license migration needed.
- **Differentiator (Phase 3):** AI-native terminal layer (command explanation, error diagnosis, NL→shell) — the gap incumbents (Termius, Blink, Prompt 3) haven't filled.

## 2. Foundation Decision

**Base: fork `migueldeicaza/SwiftTermApp`** — a complete, working open-source iOS SSH client (MIT) built on SwiftTerm. It already has: terminal view, host list, key management, themes, keyboard accessory bar.

**Planned surgery on the fork:**

| Layer | Ships with SwiftTermApp | Replace/keep |
|---|---|---|
| Terminal emulation | SwiftTerm (MIT) | **Keep** — best-in-class, actively maintained |
| SSH transport | libssh2 C wrapper | **Replace with Citadel** (MIT, pure Swift on swift-nio-ssh) — no C toolchain pain, async/await native |
| UI | SwiftUI + UIKit mix | **Keep**, modernize incrementally |
| Key storage | Keychain + Secure Enclave | **Keep** — this is hard-won code |
| Settings/host store | Local + iCloud | **Keep**, extend |

**Fallback:** if the Citadel swap proves painful in week 1, keep libssh2 for MVP and defer the swap. Transport is behind a protocol boundary (see §3) precisely so this is a contained decision.

## 3. Architecture

```
┌─────────────────────────────────────────────┐
│ SwiftUI App Shell                           │
│  HostListView · TerminalView · KeyManager   │
│  SettingsView · (P3: AIAssistPanel)         │
├─────────────────────────────────────────────┤
│ Session Layer                               │
│  SessionManager (multi-session, lifecycle,  │
│  reconnect policy, background handling)     │
├─────────────────────────────────────────────┤
│ Transport Protocol (SSHTransport)           │
│  connect / auth / openChannel / exec /      │
│  resize / sftp / portForward                │
│   ├── CitadelTransport   (primary)          │
│   └── LibSSH2Transport   (fallback)         │
├─────────────────────────────────────────────┤
│ Terminal Emulation: SwiftTerm               │
│  TerminalView ←bytes→ SessionManager        │
├─────────────────────────────────────────────┤
│ Storage                                     │
│  Keychain/Secure Enclave: private keys,     │
│    passwords                                │
│  SwiftData/CoreData: hosts, snippets,       │
│    known_hosts                              │
│  CloudKit (P2): host/settings sync          │
└─────────────────────────────────────────────┘
```

**Key design rules**
1. `SSHTransport` is a Swift `protocol` — UI and session logic never import Citadel/libssh2 directly.
2. All connection state machines are `actor`s — SSH + mobile lifecycle is a concurrency minefield.
3. Private keys never leave Keychain/Secure Enclave; signing happens via SecKey where possible.
4. Every feature behind a flag from day 1 (`FeatureFlags.swift`) — makes the free/paid split trivial in P2.

## 4. MVP Feature Cut (Phase 1 — personal daily driver)

**In:**
- Host list: add/edit/delete, host groups, quick-connect (user@host:port)
- Auth: Ed25519 + RSA keys (generate on device, import via paste/Files), password, interactive-keyboard
- known_hosts with TOFU prompt on first connect / key-change warning
- Terminal: full SwiftTerm (256-color, mouse, resize), pinch zoom, external keyboard, Ctrl/Esc/arrows accessory bar
- Multiple simultaneous sessions, swipe/tab switcher
- Reconnect-on-foreground with clear session-died UX (iOS will kill background sockets — don't fight it in MVP)
- Copy/paste, URL detection

**Out (deliberately) for MVP:**
- Mosh (huge complexity; revisit P2/P3 — this is Blink's moat)
- SFTP file browser (P2; Files.app provider is its own project)
- Port forwarding UI (transport supports it; UI in P2)
- iCloud sync, snippets, themes marketplace, iPad multi-window (P2)
- AI layer (P3)

## 5. Phase 2 — Commercial hardening
- SFTP browser + Files.app FileProvider extension
- CloudKit sync (hosts, settings, snippets — never private keys; offer encrypted export instead)
- Port forwarding (L/R/SOCKS) UI
- Snippets/macros with variables
- Free tier: full SSH client. Paid ($15–20/yr, Blink-style): sync, SFTP, forwarding, AI. Repo stays public — "pay for convenience, compile for free."

## 6. Phase 3 — AI layer (the actual moat)
- **Explain this**: select terminal output → LLM explains (errors, logs, configs)
- **NL→shell**: type intent, get command + risk annotation, confirm before send
- **Session-aware diagnosis**: last N lines as context; local redaction pass (strip IPs/secrets) before any API call
- BYO API key first (Anthropic/OpenAI-compatible endpoints — also solves mainland-China access); hosted proxy later as paid feature
- Privacy stance is the marketing story: on-device redaction, explicit per-request send, nothing streamed silently

## 7. Repo & Workflow Setup
1. Fork `migueldeicaza/SwiftTermApp` → `mikezhang09-code/<name>` (keep MIT LICENSE + attribution)
2. Branches: `main` (releasable), `dev`, feature branches
3. `CLAUDE.md` at repo root: architecture rules above, SwiftTermApp code conventions, "never touch Keychain code without tests"
4. XcodeGen or keep .xcodeproj; add a `Makefile` for build/test/lint so Claude Code can self-verify
5. Unit tests for: transport protocol conformance, known_hosts logic, key import parsing. UI later.
6. TestFlight once P1 is stable (needed anyway for >7-day sideload signing pain — a paid Apple Developer account, $99/yr, fixes the 7-day resign cycle)

## 8. Suggested Claude Code opening prompts
1. "Clone the fork, build it in Xcode, get it running on simulator; list every build error and fix them" *(SwiftTermApp's last release may need updates for current Xcode/iOS SDK — expect this to be session 1's real work)*
2. "Map the codebase: where do SSH connect/auth/data-flow live? Produce ARCHITECTURE.md"
3. "Define `SSHTransport` protocol per spec §3; wrap existing libssh2 code behind it without behavior change; add conformance tests"
4. "Implement `CitadelTransport`; add a debug toggle to switch transports at runtime"
5. Then feature-by-feature from §4, one branch each.

## 9. Risks
| Risk | Mitigation |
|---|---|
| SwiftTermApp bit-rot vs current SDK | Session 1 dedicated to build resurrection; SwiftTerm itself is current |
| Citadel gaps (some auth/kex methods) | Transport protocol + libssh2 fallback |
| iOS background socket kills | MVP: honest reconnect UX; P2/P3: Mosh or WebSocket bounce server |
| App Store review (network client rules) | Nothing unusual — dozens of SSH apps approved; no private APIs |
| Crowded market | Don't compete on SSH; compete on AI layer + bilingual (EN/中文) UX — underserved in every incumbent |
