# AI Layer — Status Review & Implementation Plan

*2026-07-18. Companion to `ios-ssh-app-spec.md` (the original claude.ai plan, spec v0.1).
This document records where the project stands against that spec and the agreed plan
for implementing the Phase 3 AI feature.*

> **Status: spec §6 is shipped.** Steps 1–4 below are done and on `main`; only the
> step-5 polish items remain.  See §8 for the shipped-state summary, the
> implementation notes worth remembering, and what still needs on-device
> verification.

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
   bilingual EN/中文 answer preference, configurable context-lines, offline/rate-limit
   error handling.

---

## 7. Shipped state (updated 2026-07-18)

| Step | Commit | Status |
|---|---|---|
| 1. Foundation (providers, keys, Test) | `047fa31` | ✅ Shipped, device-verified (OpenAI, Gemini, Vercel AI Gateway) |
| — visibility/model-list follow-up | `2dd1af3` | ✅ Two-phase answer screen, Test-fed model picker, local-terminal AI |
| 2. Explain this | `aa1d570` | ✅ Shipped, simulator-verified |
| 3. NL→shell | `064d601` | ✅ Shipped, simulator-verified |
| 4. Diagnose | `688252e` | ✅ Shipped, simulator-verified |
| 5. Polish | — | ⬜ In progress (see below) |

### What each feature ended up being

- **Providers** — `AiProviderStore` keeps configs in the app's UserDefaults suite and
  API keys in the keychain (`SwiftTermAppAiApiKey` service, reusing `KeychainTools`).
  Anthropic / OpenAI / Gemini kinds; "compatible" endpoints are the same kind with a
  custom base URL.  **Test** lists the endpoint's models (free) and loads the real
  list into the model picker; Anthropic-compatible proxies without `/v1/models` fall
  back to a 1-token message ping.
- **Explain / Diagnose** — one sheet, two modes (`AiExplainView.Mode`).  Captures the
  selection or a buffer tail, redacts, shows the exact text before sending, then
  streams the answer on a dedicated screen.  Diagnose takes more scrollback and asks
  for cause + concrete next step, with uncertainty stated plainly.
- **NL→shell** — `AiCommandView` asks for one POSIX command as JSON via
  `AiClient.completeJson`, using each provider's native structured-output parameter
  with an automatic retry on plain prompting when a proxy rejects it.  Risk badge
  (safe/caution/destructive), insert **without** a trailing newline, extra
  confirmation for destructive commands.

### Implementation notes worth remembering

- **iOS 14.7 deployment target** rules out `URLSession.bytes(for:)`, `.textSelection`,
  and `swipeActions` — SSE streaming is a `URLSessionDataDelegate` (`AiChatStream`).
- **SwiftTerm defines its own `Color`** — qualify `SwiftUI.Color` in files importing both.
- **Redaction placeholders are stable** (`[IP-1]` repeats for the same value) so the
  model can still reason about "the same host appears twice"; loopback addresses are
  allowlisted because they matter for diagnosis.
- **Verify test-bundle freshness before trusting a UI test.** An interrupted
  `xcodebuild` corrupted the UITests target's incremental build state: the build
  reported success while relinking a stale object file, so the runner silently
  executed old test code.  Fix: `rm -rf` the target's `.build` dir and `XCBuildData`,
  then confirm with `strings <UITests binary> | grep <new identifier>`.
- **XCUITest on iPad**: Form rows under the keyboard are virtualized out of the
  accessibility tree (dismiss the keyboard or swipe first), and sidebar navigation
  from a deep state is flaky — relaunching the app is more reliable.

### Verification

Simulator end-to-end tests (`testExplainEndToEnd`, `testCommandEndToEnd`,
`testDiagnoseEndToEnd`) drive the real flows against a loopback mock server
(`mock_sse.py`, all three provider wire formats + non-streaming JSON).  **The mock
server must be running on 127.0.0.1:8765 for those tests to pass** — ATS exempts
loopback, so plain HTTP works in the simulator.

Still outstanding: **device verification of Explain / Diagnose / Command against a
real provider over a real SSH session.** The mock proves the wire formats and the UI;
only the device proves the answers are useful.

## 8. Risks

- **App Store later:** BYO-key is fine (many clients do this); the pre-send privacy
  preview also doubles as review-friendliness.
- **Redaction is heuristic** — the preview-before-send is the real safety net;
  label redaction as best-effort in the UI.
- **Model churn:** IDs centralized in one table; base-URL override gives an escape
  hatch if the endpoint landscape changes.
