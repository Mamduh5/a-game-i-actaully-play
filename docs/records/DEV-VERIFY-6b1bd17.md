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

## Independent verification (6b1bd17)

Antigravity/Gemini verified all 5 writer digests above and reproduced detached composition `6b1bd17c428ea61f5e1f41afd4bb1bb11934687f` from a clean archive under pinned Godot `4.7.stable.official.5b4e0cb0f` (`GODOT_MCP_RUNTIME=off`, isolated Windows profile, `.qa-evidence/dev-composition-review-6b1bd17/`): cold import, **284/284 GUT tests (8,142 assertions, 0 failures)**, clean 227-file `Windows Player` export matching all 227 pack entries (passing all forbidden/required boundary checks), and isolated `AGIP_BOOT ... flavor=player ... renderer=gl_compatibility` boot matching `boot.log` byte-for-byte. Individual package gates and `C24`'s writer-in-progress review boundary remain in force.

| File under `.qa-evidence/dev-composition-review-6b1bd17/` | SHA-256 |
|---|---|
| `bootstrap.log` | `92caa13a01b0af7c7dd5bde87e58bd517e95ec9a5b9b80356eaf28926da66b98` |
| `import.log` | `6cc75b6af13bd933e760575e16da4586c39a2346d091ff6419d99c77e7687352` |
| `gut.xml` | `7ff25c557361d69ea8262fd0ef710c75c83bba6927221b24a40bd258dc2c089d` |
| `player-pack.txt` | `70dfa32db9ce04248e1acfbba2948b7d0d46ae8ede2f08ffb1bf4f49b126747b` |
| `boot-player.log` | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
