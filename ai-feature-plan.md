# AI Layer — Status Review & Implementation Plan

*2026-07-18. Companion to `ios-ssh-app-spec.md` (the original claude.ai plan, spec v0.1).
This document records where the project stands against that spec and the agreed plan
for implementing the Phase 3 AI feature.*

---

## 1. Spec vs. what has actually shipped

| Spec item | Planned phase | Status |
|---|---|---|
| Working SSH daily driver (hosts, keys, terminal, known_hosts) | Phase 1 | ✅ Done, plus fixes beyond spec (libssh2 1.11.0 upgrade for RSA-SHA2, host-key dialog robustness c5cc2ab/7a77f46, auth-banner surfacing 68dddfc) |
| Citadel transport swap | Phase 1 (optional) | Skipped — spec's own fallback ("keep libssh2") taken; working well |
| Reconnect UX | Phase 1 | ✅ Done (a8f11f6 — fresh-session reconnect with exponential backoff, 10s viability watchdog; tmux hosts auto-reconnect) |
| SFTP browser | Phase 2 | ✅ Done (07fe99b), plus SSH-key import over SFTP (d3a556e) — not even in the spec |
| Port forwarding -L/-D/-R UI | Phase 2 | ✅ Done (18cc353 local, cb2e8f0 dynamic+remote), plus SOCKS test button (69dab59) and in-app SOCKS browser (b237dd2) |
| iCloud sync, snippets, Files.app provider | Phase 2 | Not done (upstream snippets UI exists; not a focus) |
| Local terminal (ios_system) | Not in spec | ✅ Done anyway (ed1140c, latency fix cb52a7c) |
| Keyboards (3-mode + tmux prefix key) | Not in spec | ✅ Done (97b4bd0) |
| **AI layer (explain / NL→shell / diagnosis)** | **Phase 3 — "the actual moat"** | **Not started ← this plan** |

Conclusion: the app is ahead of the spec everywhere except the AI layer, which the
spec explicitly calls the differentiator vs. Termius/Blink/Prompt 3.

---

## 2. AI feature scope (spec §6)

1. **Explain this** — select terminal output (or grab the last screen) → Claude
   explains errors/logs/configs.
2. **NL→shell** — type intent (EN/中文) → get a command + risk annotation → confirm
   before it is typed into the session.
3. **Session-aware diagnosis** — "why did that fail?" using the last N lines of the
   buffer as context.
4. **BYO API key**, on-device redaction, explicit per-request send. Nothing streams
   silently. The privacy stance is the marketing story.

---

## 3. API approach

Swift has no official Anthropic SDK → raw HTTPS against
`POST https://api.anthropic.com/v1/messages` with `URLSession`.
Headers: `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.

Decisions:

- **Model:** default `claude-opus-4-8`; settings picker also offers
  `claude-sonnet-5` and `claude-haiku-4-5` (cheap/fast option for one-line explains).
  Model IDs live in one constants table — easy to update as models change.
- **Streaming** (`"stream": true`, SSE) for Explain/Diagnose so long answers render
  progressively: `URLSession.bytes(for:)` + line parsing of `content_block_delta`
  events. NL→shell responses are short → non-streaming.
- **NL→shell uses structured outputs** — `output_config.format` (json_schema) with a
  schema like `{command, explanation, risk: "safe"|"caution"|"destructive",
  risk_reason}`. Note: assistant prefill is **not supported** on current models;
  structured outputs is the correct replacement and guarantees parseable JSON.
- **Configurable base URL** in settings (default `api.anthropic.com`) so an
  OpenAI-compatible or proxy endpoint works — spec calls this out for
  mainland-China access. A small provider enum switches header/body shape for
  OpenAI-style endpoints.
- Prompt caching: not needed initially — requests are small and independent.
- Error mapping: 401 (bad key), 429 (rate limit, honor `retry-after`),
  529/5xx (retry with backoff) → human-readable messages in the UI.

---

## 4. Integration points (verified in this codebase)

| Need | Hook |
|---|---|
| Selected text | `TerminalView.getSelection() -> String?` (public, SwiftTerm `AppleTerminalView.swift:1326` in the pinned checkout — no SwiftTerm fork needed) |
| Last N lines / whole buffer | `Terminal.getBufferAsData(kind:encoding:)` (SwiftTerm `Terminal.swift:5189`) — take the tail |
| Injecting the approved command | `SshTerminalView.send(...)` path (`SwiftTermApp/Terminal/SshTerminalView.swift:517`) — feed bytes as if typed; **never append `\n`** — user presses return themselves (extra safety) |
| UI entry point | Terminal toolbar in `SwiftTermApp/Terminal/ConfigurableTerminal.swift` (~line 112) — already has folder (SFTP) and ⇄ (forwards) buttons; add a ✨ button opening the AI panel |
| API key storage | Keychain, following the app's existing key-material patterns (`Keys/`, `DataStore`) — never UserDefaults |
| Per-host toggles/settings | UserDefaults, same pattern as `PortForwarding.swift` defs |

---

## 5. New files

| File | Contents |
|---|---|
| `SwiftTermApp/Ai/AnthropicClient.swift` | Request/response types, SSE parsing, error mapping |
| `SwiftTermApp/Ai/Redactor.swift` | Pre-send scrub: IPv4/IPv6, hostnames, `PRIVATE KEY` blocks, `password=`/`token=`/`Authorization:` values, usernames from prompt lines. Pure function → unit-testable |
| `SwiftTermApp/Ai/AiPanel.swift` | SwiftUI sheet, three modes (Explain / Ask / Diagnose); **"what will be sent" preview** (redacted text shown before Send — the privacy story); streaming answer view; NL→shell command card with risk badge + "Insert into terminal" (styling escalates for `destructive`) |
| `SwiftTermApp/Ai/AiSettings.swift` | API key entry (Keychain-backed), model picker, base URL, redaction toggle, context-lines slider (default ~80) |

⚠️ Each new file needs **manual pbxproj registration in 4 places with 24-char
hex-only IDs** — same as the `SftpBrowserView.swift` registration in 07fe99b.

---

## 6. Build order

Each step = one commit, testable on its own. Steps 2–4 need on-device verification
(real host, real error output).

1. **Foundation** — `AnthropicClient` + `Redactor` + settings/key storage.
   Verify with a standalone `swift` script against the real API before any UI
   exists (same technique used to validate NWListener and SOCKS5 earlier).
2. **Explain this** — toolbar ✨ button; use selection if present, else last N
   buffer lines; redact → preview → send → streamed answer. Smallest end-to-end
   slice; proves the whole pipeline.
3. **NL→shell** — Ask mode with structured output + risk annotation +
   confirm-then-insert via `send()`.
4. **Diagnose** — Ask-variant that auto-attaches the buffer tail with a
   diagnosis-oriented system prompt. (True exit-code awareness would need shell
   integration hooks — out of scope for v1; buffer tail is enough.)
5. **Polish** — long-press context-menu "Explain selection" on the terminal,
   bilingual EN/中文 answer preference, offline/rate-limit error handling.

---

## 7. Risks

- **App Store later:** BYO-key is fine (many clients do this); the pre-send privacy
  preview also doubles as review-friendliness.
- **Redaction is heuristic** — the preview-before-send is the real safety net;
  label redaction as best-effort in the UI.
- **Model churn:** IDs centralized in one table; base-URL override gives an escape
  hatch if the endpoint landscape changes.
