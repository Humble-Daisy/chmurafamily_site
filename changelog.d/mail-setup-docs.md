### Changed

- The deployment guide leads with `bin/mail-setup`, adds a recipe for separating kinds of mail, and says an invite-only app sends nothing to an address with no account. `operations.md`, `bin/deploy-guide`, `forking.md` and `.env.example` are corrected to match, and `config/deploy.yml` gains commented `SIGNUP_MODE` and `WORKSPACE_ON_SIGNUP` lines.
- The boot check's mail refusal gives a staging command that works.
