# Specifications

Tracked contracts for munin's subsystems. A spec here is the agreed
shape of a feature: what exists, why, and the invariants tests and
review hold it to. Implementation follows the spec; deviations are
recorded in the implementing session's `mission_log/` entry, not by
quietly editing the spec.

Working notes, design explorations and scratch plans live in the
gitignored `plans/` area -- they are thinking, not contract.

| Spec | Status | Summary |
|------|--------|---------|
| [01_OFFLINE_SCHEMA_MIGRATION.md](01_OFFLINE_SCHEMA_MIGRATION.md) | Implemented | Schema evolution is offline: `script/munin-upgrade-db` is the only migrator; runtime code verifies the schema version at `get_dbh` and dies loudly on mismatch; `version_history` is the version stamp and audit trail |
