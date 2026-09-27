# Mission Log: Defaults.pm Refactoring

**Date:** 2026-09-27
**Branch:** test-improve

## Goal

Remove compile-time generation of Defaults.pm and make it a static file with FHS-compliant paths that distributions can patch directly.

## Background

Defaults.pm was generated at compile time by Defaults.pm.PL, which hardcoded installation paths into the Perl module. This approach had several issues:

1. **Fragile generation**: PL file required Module::Build to run at compile time
2. **Distro friction**: Distributions couldn't easily patch paths
3. **Git noise**: Generated file was in .gitignore, making changes hard to track
4. **Unnecessary complexity**: Simple path constants don't need code generation

## Changes

### Removed

- `lib/Munin/Common/Defaults.pm.PL` - Code generator

### Modified

- `lib/Munin/Common/Defaults.pm` - Now static file with FHS paths
- `Build.PL` - Removed PL_files entry for Defaults.pm
- `.gitignore` - Removed Defaults.pm exclusion

### Added

- `t/munin_common_defaults.t` - Tests that print all defaults and verify FHS compliance

## Defaults

```perl
our $MUNIN_CONFDIR    = '/etc/munin';
our $MUNIN_LIBDIR     = '/var/lib/munin';
our $MUNIN_HTMLDIR    = '/var/www/html/munin';
our $MUNIN_CGITMPDIR  = '/var/lib/munin/cgi-tmp';
our $MUNIN_DBDIR      = '/var/lib/munin';
our $MUNIN_PLUGSTATE  = '/var/lib/munin/plugin-state';
our $MUNIN_SPOOLDIR   = '/var/lib/munin';
our $MUNIN_LOGDIR     = '/var/log/munin';
our $MUNIN_STATEDIR   = '/run/munin';
our $MUNIN_PERL       = '/usr/bin/perl';
```

## Design Decisions

### Why not fuse into Config.pm?

Node modules use `$Munin::Common::Defaults::MUNIN_*` directly. Fusing would require updating all callers.

### Why static file?

- Distributions can patch directly with `sed` or `patch`
- No compile-time dependencies
- Clear diff in version control
- Follows principle of least surprise

## How to Patch

### Debian/Ubuntu

```bash
sed -i 's|/etc/munin|/etc/munin/debian|g' lib/Munin/Common/Defaults.pm
```

### Red Hat/CentOS

```bash
sed -i 's|/var/lib/munin|/var/lib/munin64|g' lib/Munin/Common/Defaults.pm
```

## Test Results

```
Defaults tests: 4/4 pass
Full suite:     27/27 programs pass (441 tests)
```
