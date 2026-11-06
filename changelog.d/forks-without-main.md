### Fixed

- Pushing from a Fork-button fork no longer fails on a missing `origin/main`, and `bin/branch-rules` creates `main` from `next` when a fork has none.
- `bin/fork`'s baseline tag names the commit the fork started from, not the template's `main`.
