### Added

- The database is backed up every hour, to an S3-compatible bucket or a folder on another disk such as a NAS, with `bin/rails backup:now`, `backup:status` and `backup:restore`. Production refuses to boot until one is configured: see the deployment guide's "Back up the database".
