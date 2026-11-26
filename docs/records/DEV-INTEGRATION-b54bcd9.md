# Approved checkpoint integration

Codex integrated the four candidates approved by Antigravity in `c01b7df` onto dev. Exact retest head `b54bcd923e433b41c23df45e6665fd1351157cc1`. Source commits and landed commits are paired below in application order.

| Package | Reviewed source | Integrated on dev |
|---|---|---|
| C01 | 991448c | f25dd1d |
| WP18 | d4e537a, 05df3d6, d9ae901 | 43bd2b6, 4a5f5b6, be04149 |
| WP21 and WP23 purchase boundary | c12580e, 23879b8, 9008677 | 2f775e0, 5067154, 4e80a65 |
| WP25 | 2c89dbf, 76ab6df | 83b0f2d, b54bcd9 |

On pinned Windows Godot 4.7, archive the head, isolate APPDATA and LOCALAPPDATA, set GODOT_MCP_RUNTIME=off, then run tools/import_project.ps1 and tools/run_gut.ps1. All 273 tests passed. Run c01_starter_probe.tscn headless at fixed 60 FPS with each arm below. All five passed. Export Windows Player, inspect the pack with tools/inspect_pack.ps1 and boot with --agip-exit-after-boot. The 217-file pack and Compatibility Player boot passed the exclusions for tests, fixtures, GUT and MCP. Against the earlier detached 284-test composition, the only runtime and test differences are the still-isolated C24 files.

| File under .qa-evidence/dev-integration/b54bcd9/ | SHA-256 |
|---|---|
| import.log | `ed01f5a81d1057d81ede73db756969f99806f6c0205ec7c16ebed69937e635d3` |
| gut.xml | `4825838315199b4eff098bb67ebb8e3118f44097734022d3f929d55493404699` |
| sword.log | `3ead3da5561ed97b6ff57b963264a85b1d8c7f9306259b330308cd1f219ae630` |
| bow.log | `f3987ecb3d1567bce4c9ed1591887a2c1b4da3f8f75a851e1e1118b91cf3a3ab` |
| bow-miss.log | `5d2779b0bdfea3a1d68a8f5a036b4dc6175245bfade2ccb4bdd96417fe81b2ef` |
| sigil.log | `c3f28f670abcd29b982ff0587fe5834126178ed0f4257636b2455e8ce065ee29` |
| undying.log | `4e6ddf5a0390ab324faeeb46882178cf36c77d4a1c7fee69d9f36568562718b3` |
| manifest.txt | `ab9ab736a577f44d5b81a2869819c7a0322f6dd11a54a8df0628f6d3206d3216` |
| boot.log | `150bd02025bc1b327f915c5215b6091ba953106ccfadee74008d89162364a3ff` |
