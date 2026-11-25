# Local QA evidence

Raw screenshots, logs, traces, receipts and export manifests live in `.qa-evidence/<change-id>/`.
Everything here except this file and `.gdignore` is ignored by Git. The tracked record
`docs/records/<change-id>.md` lists relative filenames, capture conditions and SHA-256 hashes
so a reviewer on this workstation can verify the files, and a reviewer elsewhere can request an
authorized transfer and check the hashes. The `.gdignore` file keeps Godot from importing evidence.
