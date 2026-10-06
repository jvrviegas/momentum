# Repository instructions

## GitHub account for origin

This repository's `origin` is owned by `jvrviegas`.

Whenever working with `origin` (including fetch, pull, push, or GitHub CLI operations on the origin repository):

1. Run `gh auth switch --hostname github.com --user jvrviegas` before the operation.
2. Verify with `gh auth status` that `jvrviegas` is the active account. Do not proceed if switching or verification fails.
3. Perform the requested work.
4. Always switch back to `joao-viegas-procimo` when finished, including after failures, using `gh auth switch --hostname github.com --user joao-viegas-procimo`.
5. Verify that `joao-viegas-procimo` is active again. Report any failure to restore the account.

For shell workflows, use an EXIT trap to ensure restoration on errors. Do not assume the currently active account is correct, and never include authentication tokens in commands, logs, or repository files.
