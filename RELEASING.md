# Releasing

One `vX.Y.Z` tag identifies the Hex package, `@letterpress/language`, and
`@letterpress/svelte`. The workflow builds all three artifacts once, verifies
their hashes, installs those exact tarballs in throwaway Hex/npm consumers,
and only then enters the protected `release` environment.

Configure protected `main` and `v*` rules, a
reviewer-protected `release` environment, a least-privilege npm automation
token, and a least-privilege Hex API key. Store registry credentials only as
secrets available to the protected release environment.

The local dry run is:

```bash
pnpm test:release
pnpm check:release
node scripts/release.mjs build --allow-untagged --artifact-dir dist/release
node scripts/release.mjs smoke --allow-untagged --artifact-dir dist/release
node scripts/release.mjs publish --allow-untagged --artifact-dir dist/release --dry-run
```

Use `mix git_ops.release` to prepare the next release. The configuration in
`config/config.exs` manages the Mix version, both npm versions, and
`CHANGELOG.md` together. Review the resulting commit and changelog, run
`mix check`, and dispatch a dry-run workflow before pushing the tag.
Do not remove existing release history or move a published tag.

Publication is resumable. Before the first registry write, the orchestrator
checks every target. Existing versions are skipped only when their bytes match
the release manifest; conflicting bytes abort the run. Never move or recreate
a release tag after partial publication.
