### Fixed

- The deployment guide's fnox lines for `.kamal/secrets` keep the environment first and the key file last, as the secrets spec requires; the bare `fnox get` line it showed failed three of that spec's examples.
- The deployment guide pins fnox and age in the form the workflow-audit invariant reads, and names the `install_args` line that invariant also checks.
- The deployment guide's `fnox reencrypt` commands pass `--force`, and its restore starts the deployed version, not the checkout's.
- The deployment guide shows how to keep a private deploy host's name out of a public repository.
