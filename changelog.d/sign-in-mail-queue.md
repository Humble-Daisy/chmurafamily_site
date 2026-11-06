### Fixed

- Sign-in links and other `deliver_later` mail run on the `mailers` queue, which the worker claims ahead of backups and sweeps.
