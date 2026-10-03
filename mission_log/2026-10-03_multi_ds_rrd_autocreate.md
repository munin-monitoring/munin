# Mission Log: Multi-DS RRD Auto-Creation + ds_rrd/Soft-Delete

**Date:** 2026-10-03
**Context:** Enhance the multi-field RRD work: auto-create one multi-DS RRD
per service when possible. Validated design decisions with the user before
and during implementation.

---

## What We Did

### Part 1: Auto multi-DS creation (UpdateWorker.pm)

New services group their fields into one RRD file per compatibility group:

- **Grouping criterion:** fields share a file iff their `RRDs::create`
  would produce the same effective layout -- same step (update_rate) and
  same RRAs (graph_data_size). `normal`/`huge`/`debug` resolutions
  hard-code the 300s step (pre-existing behavior), so update_rate does not
  split those groups; custom resolutions key on (update_rate, resolution)
  because RRAs are computed from it. Type/min/max are per-DS and never
  affect grouping.
- **Naming:** `{host_path}-{service}.rrd` (no type in the filename -- type
  lives in the DS name, e.g. `idle-g`, `rx-d`). Second+ incompatible
  groups get `-2`, `-3` suffixes. The plan doc's `{service}-{type}.rrd`
  was rejected: a group may mix types.
- **Late fields:** RRDtool cannot add a DS to an existing file, so fields
  appearing after the multi-DS file exists fall back to individual
  `{service}-{field}-{type}.rrd` files (user-validated).

### Part 2: Grouped template updates

Multi-DS files make per-field updates impossible: a lone template update
marks every unlisted DS as NaN for that timestamp, and the sibling fields'
updates at the same timestamp are then rejected. The fetch path now buffers
`{rrd_file => {when => {ds_name => value}}}` and flushes one RRDtool update
per (file, template), walking timestamps in order and vectorizing
consecutive rows that share a template (preserves rrdcached batching).
Fields with no value at a timestamp are simply omitted -- for a deleted
field "just stop updating is enough" (user): its DS goes stale, nothing
else is required.

### Part 3: ds_rrd table + soft delete (user-directed schema change)

- `ds_rrd (ds_id PK, file, field, alias)` -- regular columns, owned by the
  RRD creation loop, **never touched by the plugin-config attribute
  diff**. This structurally fixes the bug the tests exposed: the old
  key/value diff deleted `rrd:file`/`rrd:field` every cycle (plugins never
  report them), which clobbered legacy `rrd:field = "42"` and would have
  regrouped late fields into multi-DS files that do not hold their DS --
  breaking the whole file's updates.
- Migration in `_db_init`: copy `rrd:file`/`rrd:field`/`rrd:alias` from
  ds_attr (COALESCE `'42'` for pre-`rrd:field` files), then retire those
  key/value rows. Idempotent (`NOT EXISTS` guard).
- `ds.deleted` soft-delete column. Fields that disappear from the config
  are soft-deleted: row, attrs, RRD mapping and state all survive; the
  update path stops writing; a reappearing field resurrects (deleted=0)
  with continuous RRD history. The old hard-delete + attr-purge block is
  gone.
- Readers switch to `ds_rrd` and hide soft-deleted fields: Graph.pm (both
  queries, incl. `get_alias_rrdfile`), Limits.pm (evaluation + notification
  queries; the CDEF *source* lookup deliberately keeps soft-deleted fields
  so CDEFs keep working against last-known data), HTML.pm (overview
  badges, per-service state, `_get_params_fields`).

---

## What We Learned

1. **RRDtool boundary-update semantics are a trap for test assertions.**
   With a file start far in the past (production uses `now - 12h`) and
   heartbeat 600, only the *last* update's value is visible at its row;
   earlier boundary updates consolidate to NaN. With a tight start, every
   update's value lands at its own row. Do not assert RRD history rows;
   assert `RRDs::info` `ds[X].last_ds` instead -- it verifies the actual
   contract (value landed in the right DS of the right file) independent
   of consolidation quirks.
2. **`map { $1 => ... } grep { /pat/ }` yields an empty capture** in
   modern perl -- `$1` does not survive from grep into map. Run the regex
   inside the loop.
3. **`RRDs::update($file, "-t", "a:b", "$t:v1:v2")`** (options after the
   filename, RRDs 1.7002) verified empirically before building on it.
4. **Beware `-f $relative_path`**: RRD paths in ds_attr/ds_rrd are
   relative to dbdir; existence checks must be dbdir-qualified.
5. Tests found the real bug (rrd:* attr deletion) faster than review did:
   a 3-cycle scenario (create -> late field -> next cycle) is what
   exposes state-loss bugs that single-cycle tests hide.

## Test Coverage

| Area | Tests |
|------|-------|
| Grouping key semantics | 6 |
| `_flush_rrd_updates` batching/ordering/template (mocked RRDs) | 10 |
| Cycle 1: auto multi-DS create + layout + data | 26 |
| Cycle 2: late-field fallback | 6 |
| Cycle 3: mapping stability across cycles | 4 |
| Cycle 4: deleted field -- mapping kept, updates stop | 7 |
| Cycle 5: resurrect with history | 4 |
| Legacy per-field layout untouched | 4 |
| Soft-delete lifecycle (_db_service) | 9 (dbstate Scenario 14) |

Full suite: 36 files / 513 tests green, lint-munin green.

## Commits

1. `schema: ds_rrd table (file/field as columns) + ds.deleted soft-delete`
2. `feat: auto-create multi-DS RRDs + grouped template updates`
3. docs (this log + plan update)
