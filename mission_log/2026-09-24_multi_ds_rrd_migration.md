# Mission Log: Multi-DS RRD Migration + Session Cleanup

**Date:** 2026-09-24
**Context:** Continuing multi-DS RRD initiative. Building offline migration tool, fixing logging issues, cleaning up codebase, improving CI.

---

## Session Summary

27 commits, 17 files changed, +1411/-335 lines. Work spanned CI optimization, logging cleanup, code removal, and building the `munin-migrate-rrd` tool through 4 implementation iterations.

---

## What We Did

### Part 1: CI and Build Cleanup

**Commits:** `59eaeac57` through `ac8ccf87b` (10 commits)

Optimized GitHub Actions workflow and Docker build:

1. Added build artifacts to `.gitignore` (cover_db, .selectre, etc.)
2. Merged build+lint jobs to avoid duplicate Docker image builds
3. Made lint/perlcritic blocking before expensive coverage run
4. Added perlcritic to dev container (was missing)
5. Fixed lint issues across codebase (trailing whitespace, mutating list functions, return undef, shellcheck)
6. Removed COPY from Dockerfile -- always mount source with `-v`
7. Made lint output go to stdout instead of files
8. Removed redundant critic step (already in lint target)
9. Fixed GITHUB_TOKEN passing to coveralls container
10. Added Docker image caching between CI runs
11. Added git safe.directory for container ownership
12. Included `script/` in coverage via `blib/script`

**Key decision:** Lint-munin (perlcritic on lib/script) blocks CI. Lint-plugins/spelling/whitespace are non-blocking (too many pre-existing issues).

### Part 2: Logging Cleanup

**Commits:** `2b74d20ae`, `8aeb4bd74`, `c53a69994`

Audited and fixed logging levels across `lib/Munin/Master/*.pm`:

1. Demoted `get_dbh` from INFO to DEBUG (called frequently, not useful at INFO)
2. Removed redundant `[INFO]`, `[DEBUG]`, `[WARNING]` prefixes from log messages -- the logging framework already adds these and strips them from output
3. Demoted RRD create messages from INFO to DEBUG (routine operation)

**Logger behavior:** `Munin::Common::Logger` adds `[info]`, `[debug]`, etc. to output, and strips matching prefixes from messages. `[WARN]` was not being stripped (regex only matches `[WARNING]`).

### Part 3: CDEF Engine Fix

**Commit:** `b77dee70e`

Fixed Limits.pm CDEF engine to use `rrd:field` attribute for DS name lookup:

**Before:** Used Munin field name directly as RRD DS name in DEF statements
```perl
push @xport_args, "DEF:${tok}=$rrd_files{$tok}:$tok:AVERAGE"
```

**After:** Looks up `rrd:field` attribute to get actual RRD DS name
```perl
my $rrd_field = $rrd_fields{$tok} // $tok;
push @xport_args, "DEF:${tok}=$rrd_files{$tok}:$rrd_field:AVERAGE"
```

**Why:** SampleRRD creates RRDs with DS name `42`, but CDEF expressions reference field names like `idle`, `user`. The `rrd:field` attribute maps Munin names to RRD DS names.

### Part 4: Code Cleanup

**Commit:** `f61b63b8f`

Removed unused functions from `Munin::Master::Utils`:

- Removed: `munin_get_bool`, `munin_get`, `munin_get_rrd_filename`, `munin_get_node_name`, `munin_get_node_loc`, `munin_get_node`, `munin_set_var_loc`, `munin_set`, `munin_find_field_for_limits`, `munin_get_children`, `munin_has_subservices`
- Kept: `munin_mkdir_p`, `exit_if_run_by_super_user`, `print_version_and_exit`
- Removed 205 lines of dead code and POD documentation

### Part 5: UpdateWorker.pm Stateful

**Commit:** `5fcca9cdd`

Made UpdateWorker.pm check if `rrd:file` already exists before setting:

**Before:** Always overwrote rrd:file and rrd:field
```perl
$sth_ds_attr->execute($ds_id, "rrd:file", $rrd_file);
$sth_ds_attr->execute($ds_id, "rrd:field", "42");
```

**After:** Only set for new fields
```perl
$sth_check->execute($ds_id, 'rrd:file');
my ($existing) = $sth_check->fetchrow_array;
if (!defined $existing) {
    $sth_ds_attr->execute($ds_id, "rrd:file", $rrd_file);
    $sth_ds_attr->execute($ds_id, "rrd:field", $rrd_field);
}
```

Added `_get_rrd_field_name()` helper that returns `{field}-{type}` format (e.g., `idle-g`).

### Part 6: munin-migrate-rrd Tool

**Commits:** `d99c29d89` through `2b9dd678d` (7 commits)

Built offline tool to migrate RRD files between single-DS and multi-DS formats. Went through 4 implementation iterations:

#### Iteration 1: xport/update (commit `d99c29d89`)

Initial approach using `RRDs::xport` + `RRDs::update`:

```perl
# Export from input
my ($start, $end, $step, $nb, $cols, $values) = RRDs::xport(...);
# Update output
RRDs::update($out_file, "$when:$val");
```

**Problem:** RRDs::xport auto-scales step for large time ranges. 30-day lookback produced 22-hour steps instead of 5-minute steps.

**Fixed:** Reduced lookback to 1 day. But data conversion (float -> string -> float) is undesirable.

#### Iteration 2: XML string manipulation (commit `fef6815f9`)

Switched to XML dump/restore:

```perl
sub dump_xml { RRDs::dump -> read file -> return string }
sub extract_ds { regex to find <ds>...</ds> block }
sub restore_xml { write string -> RRDs::restore }
```

**Problem 1:** `<cdp_prep>` contains `<ds>` blocks for each data source. Regex `s/<cdp_prep>.*?<\/cdp_prep>/.../s` corrupted XML because the replacement cdp_prep had wrong structure.

**Problem 2:** Even with correct cdp_prep replacement, rows from single-DS inputs have 1 `<v>` per row, but multi-DS output needs N `<v>` per row.

**Root cause:** Can't just concatenate XML fragments when source and target have different DS counts.

#### Iteration 3: XML::LibXML DOM (commit `e24ee7338`)

User suggested: "can we use real XML routines, instead of regex?"

```perl
my $dom = XML::LibXML->load_xml(location => $xml_file);
my $ds_node = $dom->findnodes("/rrd/ds[name='$name']");
my $new_ds = $out_dom->importNode($ds_node, 1);
```

**Problem:** `importNode` on RRA nodes corrupted `<database>` content. Row elements got mangled during clone. DOM node cloning doesn't work reliably for complex nested structures with mixed content.

#### Iteration 4: Hybrid DOM + row interleaving (commit `64bffe5ae`, final)

Use DOM for structure, build rows manually:

1. **Parse** each input RRD with XML::LibXML
2. **Extract header** (version, step, lastupdate) from first input
3. **Extract DS blocks** via DOM, rename via `findvalue('name')` + `removeChildNodes` + `createTextNode`
4. **Extract RRA metadata** (cf, pdp_per_row, xff) from first input
5. **Build rows** by interleaving `<v>` values from each input
6. **Regenerate cdp_prep** with correct number of `<ds>` entries

```perl
# For each row in RRA:
for my $row_idx (0..$n_rows-1) {
    my $row = $out_dom->createElement('row');
    for my $i (0..$#$group) {
        my $src_row = $input_rows[$i][$row_idx];
        for my $v_node ($src_row->findnodes('v')) {
            $row->appendChild($out_dom->importNode($v_node, 1));
        }
    }
    $database->appendChild($row);
}
```

**Split mode:** Extract specific DS index from multi-DS source:
```perl
my @v_nodes = $src_row->findnodes('v');
$row->appendChild($out_dom->importNode($v_nodes[$ds_idx], 1));
```

#### Bugs Fixed During Development

1. **DS name whitespace:** XML has `<name> 42 </name>`, XPath `name='42'` doesn't match
   - Fix: Trim whitespace in lookup: `$name =~ s/^\s+|\s+$//g`

2. **RRA row count:** Script used first RRA's row count for all RRAs
   - Fix: Get row count per RRA: `my @rows = $rras_i[$rra_idx]->findnodes('database/row')`

3. **NodeList scalar:** `scalar $dom->findnodes(...)` fails in newer XML::LibXML
   - Fix: Assign to array first: `my @nodes = $dom->findnodes(...); scalar @nodes`

4. **Split row extraction:** Was copying all `<v>` from source row
   - Fix: Extract specific DS index based on mapping

5. **END block timing:** `END { remove_tree }` ran before `done_testing()`
   - Fix: Removed END block (tempdir has CLEANUP=>1)

6. **cdp_prep content:** Empty `<cdp_prep></cdp_prep>` caused restore failures
   - Fix: Regenerate with proper `<ds>` entries for each output DS

7. **Help output:** POD was removed during rewrite
   - Fix: Added minimal POD back

---

## API Design

```bash
# Merge: N single-DS -> 1 multi-DS
munin-migrate-rrd \
  -i cpu-idle-g.rrd:42 -o cpu-g.rrd:idle-g \
  -i cpu-user-g.rrd:42 -o cpu-g.rrd:user-g

# Split: 1 multi-DS -> N single-DS
munin-migrate-rrd \
  -i cpu-g.rrd:idle-g -o cpu-idle-g.rrd:42 \
  -i cpu-g.rrd:user-g -o cpu-user-g.rrd:42

# Append: add DS to existing file (with backup)
munin-migrate-rrd --append \
  -i cpu-steal-g.rrd:42 -o cpu-g.rrd:steal-g

# Comma syntax
munin-migrate-rrd \
  -i cpu-idle-g.rrd:42,cpu-user-g.rrd:42 \
  -o cpu-g.rrd:idle-g,user-g
```

**Spec:** `file:ds` format. `-i` maps to `-o` positionally. Multiple `-i` to same `-o` = merge. Single `-i` to multiple `-o` = split.

---

## What We Learned

### Technical

1. **RRD XML structure:**
   ```
   <rrd>
     <version>0003</version>
     <step>300</step>
     <lastupdate>TIMESTAMP</lastupdate>
     <ds><name>FIELD</name><type>GAUGE</type>...</ds>
     <rra>
       <cf>AVERAGE</cf>
       <pdp_per_row>1</pdp_per_row>
       <cdp_prep><ds>...</ds></cdp_prep>  <!-- one per DS -->
       <database><row><v>VAL</v><v>VAL</v></row></database>  <!-- one <v> per DS -->
     </rra>
   </rra>
   ```

2. **cdp_prep is per-DS:** Each RRA has one `<ds>` in `<cdp_prep>` for each data source. Must regenerate when changing DS count.

3. **Row values are positional:** `<row><v>10</v><v>20</v></row>` means first DS=10, second DS=20. Must interleave correctly.

4. **RRA row counts vary:** AVERAGE might have 576 rows, MIN might have 432. Must handle each RRA independently.

5. **DOM importNode is unreliable:** For complex structures with mixed content (elements + text + comments), manual construction is safer.

6. **XML::LibXML NodeList quirks:** `scalar $dom->findnodes(...)` doesn't work in newer versions. Must assign to array first.

### Process

1. **4 iterations to get it right:** xport/update -> string XML -> DOM -> hybrid. Each taught us more about the problem.

2. **User guidance saves time:** "can we use real XML routines" redirected us from a dead end.

3. **Test-first catches bugs:** RRA row count bug was caught immediately by tests.

4. **Logging audit was valuable:** Found and fixed redundant prefixes, wrong levels, and the `rrd:field` bug.

---

## Test Coverage: 30 Tests

| Category | Tests | What's Verified |
|----------|-------|-----------------|
| Merge | 8 | basic, three inputs, comma syntax, types preserved, DS properties (heartbeat/min/max), RRA structure, data values, NaN handling |
| Split | 4 | basic, DS properties, RRA structure, data values |
| Append | 5 | basic, DS properties, RRA structure, multiple DS, backup preservation |
| Validation | 9 | no overwrite, RRA mismatch, count mismatch, collision, missing input, DS not found, no args, step mismatch, RRA mismatch |
| Misc | 4 | dry run, help, auto-create dir, COUNTER type |

---

## Files Changed

| File | Lines | Purpose |
|------|-------|---------|
| `script/munin-migrate-rrd` | +432 | Migration tool |
| `t/munin_migrate_rrd.t` | +788 | Test suite |
| `.github/workflows/build-n-test.yml` | +45/-83 | CI optimization |
| `Dockerfile.dev` | +12/-2 | Dev container updates |
| `Makefile` | +15/-22 | Build targets |
| `.gitignore` | +4 | Ignore patterns |
| `lib/Munin/Master/Graph.pm` | +1/-1 | is_int fix |
| `lib/Munin/Master/Limits.pm` | +15/-3 | CDEF rrd:field fix |
| `lib/Munin/Master/Update.pm` | +1/-1 | get_dbh debug |
| `lib/Munin/Master/UpdateWorker.pm` | +32/-5 | Stateful rrd:file |
| `lib/Munin/Master/Utils.pm` | +6/-205 | Remove dead code |
| `lib/Munin/Common/Logger.pm` | +1/-1 | Trailing whitespace |
| `lib/Munin/Master/ConfigParser.pm` | +1/-1 | Mutating list fix |
| `lib/Munin/Master/Static/CGI.pm` | +2/-2 | Strict/warnings |
| `lib/Munin/Plugin/SNMP.pm` | +1/-1 | Trailing whitespace |
| `script/munin-get` | +1/-1 | Shellcheck quote |

---

## Design Decisions

1. **COPY semantics:** Default behavior preserves all DS properties (type, heartbeat, min, max). No data transformation.

2. **RRA validation:** Inputs to same output must share RRA structure. Fails fast on mismatch.

3. **No overwrite by default:** Must use `--append` to add DS to existing file. Prevents accidental data loss.

4. **Backup on append:** Original file saved as `.bak` before modification.

5. **Deferred input removal:** Input files removed after all outputs are created. Safe for split operations where same input feeds multiple outputs.

6. **ffmepg-style API:** `-i input:ds -o output:ds` mapping. Intuitive for users familiar with ffmpeg.

---

## What We'd Do Differently

1. **Start with DOM approach:** The xport/update and string manipulation phases took significant time. Starting with DOM would have been faster.

2. **Research RRD XML structure first:** Understanding cdp_prep/row structure upfront would have avoided the string manipulation dead end.

3. **Write more edge case tests earlier:** Some bugs (like RRA row count) could have been caught sooner with better initial test coverage.

4. **Document the XML structure:** Having a reference document for RRD XML format would have helped.

---

## Next Steps

1. **Integration:** Update `UpdateWorker.pm` to create multi-DS RRDs for new services
2. **Migration:** Create `munin-migrate-rrd --migrate-all` for batch migration
3. **Documentation:** Update Munin docs with new RRD format
4. **Monitoring:** Track migration progress in production

---

## Session 2: Test Multi-DS RRD Support (2026-09-25)

**Commit:** `7b46e2a9c`

### What We Did

Updated `SampleRRD` and `SampleDB` to generate both old-style (single-DS) and new-style (multi-DS) RRD files for testing.

#### SampleRRD Changes

- **Old-style hosts** (aesir, asynjur, svartalfar): Single-DS RRDs with DS name `42`
- **New-style hosts** (localhost, acme.com): Multi-DS RRDs for cpu, memory, network services

File naming:
- Old style: `{svc}-{field}-{type_id}.rrd` (e.g., `cpu-idle-g.rrd`)
- Multi-DS: `{svc}.rrd` (e.g., `cpu.rrd`)

DS naming:
- Old style: DS name is `42`
- Multi-DS: DS name is `{field}-{type_code}` (e.g., `idle-g`, `user-g`)

#### SampleDB Changes

Sets `rrd:file` and `rrd:field` correctly:
- Old style: `rrd:file = {svc}-{field}-{type_id}.rrd`, `rrd:field = 42`
- Multi-DS: `rrd:file = {svc}.rrd`, `rrd:field = {field}-{type_code}`

### Verification

All 83 tests pass:
- Graph: 4/4
- Limits: 43/43  
- Limits CDEF: 6/6
- Migrate RRD: 30/30

Graph generates PNGs for both old-style and multi-DS hosts. Limits correctly reads `rrd:field` to query the right DS from shared RRD files.

---

## Commands Used

```bash
# Run tests
docker run --rm --shm-size=128m --add-host testing.acme.com:127.0.0.1 \
  -v $(pwd):/app munin-dev sh -c 'perl Build.PL && perl -Iblib/lib -It/lib t/munin_master_lifecycle.t'

# Run migrate tests
docker run --rm -v $(pwd):/app munin-dev perl -It/lib t/munin_migrate_rrd.t

# Lint
docker run --rm -v $(pwd):/app munin-dev sh -c 'perl Build.PL && make lint'

# Test migrate tool directly
perl -Ilib script/munin-migrate-rrd --dbdir=/tmp/test \
  -i input.rrd:42 -o output.rrd:myfield
```
