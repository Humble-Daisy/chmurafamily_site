### Added

- The database is backed up every hour to an S3-compatible bucket, with `bin/rails backup:now`, `backup:status` and `backup:restore`. Production refuses to boot until `OBJECT_STORAGE_BUCKET`, `OBJECT_STORAGE_REGION` and the bucket's key in credentials are set: see the deployment guide's "Back up the database".
