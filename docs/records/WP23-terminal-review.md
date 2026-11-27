# WP23 Live Defeat Terminal Settlement — Independent Review

Tracked separately on `dev` so isolated `work/wp23-terminal` can integrate without extra conflicts in [WP23.md](WP23.md).

## Independent live defeat terminal settlement review (381cce4)

- **Reviewer / verdict:** Antigravity/Gemini — **CHECKPOINT APPROVED** on isolated `work/wp23-terminal` commit `381cce4b5117733c43243ca184f0a8c2fb438ce6` (base `43453cfdd7dc766f2d949b34f5439f5e8bb02c76`, handoff `4c2ee8b515ede716c76bd8d5076d959bbc7e0e48:docs/records/WP23.md`, `dev` pointer `d4c9821`). Package `WP23` remains **`IN PROGRESS`** pending active-group storage resumption, playable run assembly, live victory entitlements, and separate guest reconciliation (`WP24` and `WP26` remain gated).
- **Verified writer & clean-archive evidence:**
  - All 20 writer SHA-256 digests referenced in `4c2ee8b:docs/records/WP23.md` (including `marker-rendered/readback.log` and reconciled `live-defeat-composition/run_authority.gd`) verified verbatim on disk under `.qa-evidence/WP23/`.
  - Independent clean-archive verification of `381cce4` under pinned Godot `4.7.stable.official.5b4e0cb0f` (`GODOT_MCP_RUNTIME=off`, isolated `APPDATA`/`LOCALAPPDATA`) passed cold import, **347/347 GUT tests (14,108 assertions, 0 failures/errors)**, and clean 238-file `Windows Player` export/boot (`AGIP_BOOT` clean, zero dev/test/MCP leaks).
  - Independent negative counterexample (`43453cf` base + `381cce4:tests/unit/test_starter_encounter.gd`) reproduced **1 failure** in `test_live_defeat_waits_for_currency_and_closing_marker_then_publishes_once`, confirming the new test genuinely fails before the fix.
  - Disposable `Windows Dev` export of `dev/fixtures/wp23_terminal_defeat_probe.tscn` passed all four arms (`money` and `marker`, headless and rendered `960×540`) plus four separate cold `read` processes (`balance = 7`, `generation = 3`, `clear = true`). Visually inspected rendered `waiting.png` (`Saving run earnings` while living pose and attack ring hold) and `defeat.png` (`Defeated · Earnings saved` after durable recovery).
  - Independent coexistence composition (`git merge-tree --write-tree 381cce4 e96da91` + `dev` `35b156f:tests/unit/test_idle_realm_arrival.gd` + reconciled `.qa-evidence/WP23/live-defeat-composition/run_authority.gd`) passed cold import and **351/351 GUT tests (14,322 assertions, 0 failures/errors)**.
- **Independent adversarial probe (`WP23-terminal-review-r6/adversarial-probe.json`):**
  - Repeated 5 consecutive refused `close_tick()` retries on both money COMMIT (`0`) and closing-marker COMMIT (`1`) confirmed `movement_acknowledgement` stays `0`, `checkpoint()` and `prepare_orderly_suspension()` return `{}`, `view_for()` / `movement_state()` / `party_statuses()` stay withheld, late `OrdinaryCurrency.accrue()` is `FENCED`, recovery publishes exactly `1` outcome (`outcomes_count = 1`, zero combat replay) and advances `movement_acknowledgement` to `1`, post-defeat `close_tick()` returns `false`, and cold reopen verifies `balance = 13`, `generation = 3`, `ReopenStatus.CLEAR`.
  - Confirmed `settle_orderly_quit()` called while holding an unpublished losing tick safely flushes earnings and writes the closing marker once storage recovers (`quit_ok = true`, `after_quit_tick = false`, `balance = 13`, `generation = 3`, `clear = true`).

| File under `.qa-evidence/` | SHA-256 |
|---|---|
| `WP23-terminal-review-r6/import.log` | `267bcf128931b3c7abbad185340d7bfcb0390fd323ddb43bc0925a41149198c6` |
| `WP23-terminal-review-r6/gut.xml` | `c8f23befd18ace89817d98bf1f9919e43a78183f812d11f9f118b313b1b37259` |
| `WP23-terminal-review-r6/player-manifest.txt` | `299280283450d60ffcb70c7cfd075642b208cd7cc8f909ec809c110593bf1493` |
| `WP23-terminal-review-r6/player-boot.log` | `80d555126405d79f1567a7613b6f9f2a99f4c24770caf6d6259f9ec094ca584f` |
| `WP23-terminal-review-r6/money-headless/runtime.log` and `money-rendered/runtime.log` | `722a9645aef397f6e2e7ac432ed5726b3e84d5763011c5c9980c9ee21dbf3f2c` |
| `WP23-terminal-review-r6/marker-headless/runtime.log` and `marker-rendered/runtime.log` | `44d9fb19f742152791eedb6dd2e004facfe699a4817a1a27f727ffdd3bdbc570` |
| `WP23-terminal-review-r6/{money,marker}-{headless,rendered}/readback.log` | `131099210e94b881417540e6ce5a5a6b0cd4be825a0285db06a627898056c69a` |
| `WP23-terminal-review-r6/money-rendered/waiting.png` and `marker-rendered/waiting.png` | `f47b458e46cfec0f97392fab1ba85f274db8b211a9a607fe30be51d106fae5fa` |
| `WP23-terminal-review-r6/money-rendered/defeat.png` and `marker-rendered/defeat.png` | `0a8d083b963709dfd6cc79f0c13faf6ac1951f5b45078c310e9cd780bf41f23c` |
| `WP23-terminal-review-r6/adversarial-probe.json` | `d11265f1c9eb36a70d132d6fca3d8c2c6bddf7653454c67e02dd402aca16f167` |
| `coexist-review-r6/gut.xml` | `f73c084d2cdd45faccd077f52df204b55673a0b99b1323c47e387a141d819afb` |
