### Changed

- The deployment guide leads with `bin/mail-setup` and adds a recipe for separating kinds of mail.
- The docs say an invite-only app sends nothing to an address with no account, and how to create the first account in production.
- `config/deploy.yml` gains commented `SIGNUP_MODE`, `WORKSPACE_ON_SIGNUP` and `TENANCY_SHARED_WORKSPACE_SLUG` lines.
- The boot check's mail refusal gives a staging command that works.
