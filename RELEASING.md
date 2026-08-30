# Releasing

One `vX.Y.Z` tag identifies the Hex package, `@letterpress/language`, and
`@letterpress/svelte`. The workflow builds all three artifacts once, verifies
their hashes, installs those exact tarballs in throwaway Hex/npm consumers,
and only then enters the protected `release` environment.

Before the first release, configure protected `main` and `v*` rules, a
reviewer-protected `release` environment, npm trusted publishing, and a
least-privilege Hex API key. Do not put registry credentials in repository or
general CI secrets.

The local dry run is:

```bash
pnpm test:release
pnpm check:release
node scripts/release.mjs build --allow-untagged --artifact-dir dist/release
node scripts/release.mjs smoke --allow-untagged --artifact-dir dist/release
node scripts/release.mjs publish --allow-untagged --artifact-dir dist/release --dry-run
```

For the first release, remove the placeholder changelog and let GitOps create
the initial history in the release commit. Update the Mix and both npm package
versions together. Dispatch a dry-run workflow from that commit before pushing
the tag.

Publication is resumable. Before the first registry write, the orchestrator
checks every target. Existing versions are skipped only when their bytes match
the release manifest; conflicting bytes abort the run. Never move or recreate
a release tag after partial publication.
