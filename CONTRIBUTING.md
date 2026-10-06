# Contributing

## Commit messages

Use Conventional Commits: `<type>(<scope>): <summary>` (the scope is optional).

- `feat`: new functionality; normally a minor release.
- `fix`: bug fix; normally a patch release.
- `feat!`, another type with `!`, or a `BREAKING CHANGE:` footer: breaking change; normally a major release.
- `chore`, `docs`, `refactor`, `test`, `ci`, `style`, `build`, and `perf`: no release impact unless explicitly breaking.

Release versions and curated changelog entries are derived from commits since the latest `v*` tag. Confirm the version before preparing each release. While Momentum is in `0.x`, versions are provisional; moving to `1.0.0` is an explicit stability decision.

## Releases

Prepare version and changelog changes on `release/vX.Y.Z`, then open a PR to `main`. After merging, tag the release commit and publish a GitHub Release. Early-stage releases are marked as prereleases.

`MARKETING_VERSION` is the public version. `CURRENT_PROJECT_VERSION` must increase with every release because Sparkle compares build numbers, including when the public version is reset from an unreleased `1.0` to `0.1.0`.

The distribution procedure and signing/notarization prerequisites are documented in `scripts/release.sh`. Do not publish development-signed builds as notarized installers. For an early prerelease without distribution signing, publish source only. Do not use the script's `--publish` mode for a prerelease without adapting its publishing flags: it currently creates a regular GitHub Release.
