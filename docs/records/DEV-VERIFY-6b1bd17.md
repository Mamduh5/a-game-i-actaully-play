# Integrated checkpoint verification

Codex verified detached revision `6b1bd17c428ea61f5e1f41afd4bb1bb11934687f`. Reconstruct from [the preceding composition](DEV-VERIFY-49ec5e2.md) at `49ec5e2` by applying `d9ae901`, `9008677`, `2c89dbf` and `76ab6df` in order. The detached worktree is available locally under `.qa-evidence/dev-composition/full-checkpoints`. Reviewers can reproduce from a separate archive. The individual review heads and dispositions remain in the [plan status table](../IMPLEMENTATION_PLAN.md#plan-workflow).

A clean archive, isolated Windows profile, Godot 4.7.stable.official.5b4e0cb0f, MCP runtime off and pinned templates produced 284/284 passing GUT tests, 8,142 assertions. Run the repository import and GUT scripts, export Windows Player, then run the pack inspector. The 227-file pack contains the app, interaction frame and personal progression scripts. Exclusion checks passed for tests, fixtures, GUT, MCP and the MCP autoload. Headless release boot with `-- --agip-exit-after-boot` reported player flavor and Compatibility rendering. The shell boot and controlled tests support integration compatibility. Independent reviews, native gameplay and the full-content readiness gate remain outstanding.

| File under `.qa-evidence/dev-composition/6b1bd17/` | SHA-256 |
|---|---|
| `import.log` | `6002e706d121d50f5f88eb19066ae41215b3ca4ee45482e0568b2eaf4544be9c` |
| `gut.xml` | `48ff3b1f2b5b78ee8ff4f2c006c1291e7e6a8d29a577fdda14703fa5772b9220` |
| `export.log` | `149d1b5623c70e9bc2f27cab028bbf11aac14a44c1bfb2ffb3938b0135ab30b0` |
| `manifest.txt` | `6c1f86ef93d87aceb271b303d4c63d332710394f769e624310551dbaeb5e3b7f` |
| `boot.log` | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
