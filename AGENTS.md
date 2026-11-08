# Working on Snowfolio

Follow `docs/MODERNIZATION_PLAN.md` and the user's current instructions. Preserve essential features, user documents, licenses, and verified evidence while completing the modernization.

## Storage housekeeping

The user explicitly wants temporary items kept only while needed, then cleared when obsolete. This is a standing working preference.

- Reuse one current core build cache and one current app build location for routine work. Preserve any app bundle the user is running or relying on.
- Isolated before/after, sanitizer, or reproduction builds are allowed while an investigation needs them. Once results are captured and that check is finished, clean their regenerable build output rather than leaving another permanent cache.
- Retain compact logs, measurements, relevant screenshots, and source/version references. Keep large recordings, exported system logs, and duplicate downloads only while they support an unresolved issue or a necessary reference. Retire them once that need ends.
- Before finishing a verification cycle, review the temporary artifacts it created and clear obsolete copies. Check ownership and active processes before cleaning; never broadly clear `/tmp`, shared development caches, or another project's files.
- Use standard build-tool cleanup for regenerable caches. Follow the user's Trash preference for retired project files; do not empty Trash or remove chat history as part of routine project cleanup.
- Record material cleanup in `docs/validation/project-cleanup.json`. Storage measurements and retention decisions belong in `docs/validation/storage-footprint.json`.

Avoid retaining per-feature build directories after acceptance. The earlier accumulation of obsolete validation builds must not recur.
