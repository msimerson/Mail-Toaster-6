# AGENTS.md

This file provides guidance to coding assistants when working with code in this repository.

## Working Agreement

- Never run history- or remote-mutating commands (`git commit`, `git push`, `git tag`, `gh pr create`) unless explicitly asked. Make changes only; the human reviews, commits, and pushes.
- Propose a commit message in Conventional Commit format, imperative mood.
- Update `Changes.md`: one terse clause per change, minimal markup. Rationale belongs in the PR. The comment rules below apply to bullets too.

## Technical Standards

- Consistency: Compatibility is important, only break it for Good Cause.
- Research: Identify the relevant RFC(s). Analyze existing implementation and verify conformance.
- Use Conventional Commit format for all commit messages.
- POSIX compliance is always preferred — use `sed -i.bak` (not `sed -i ''`) for in-place edits; use `mkdir -p` instead of bare `mkdir`.
- Most provision scripts run `set -e`. A bare `_var=$(cmd)` ends the script when `cmd` exits non-zero, silently and before anything downstream runs. When "absent" is an expected answer, write `_var=$(cmd 2>/dev/null) || _var=""`.
- `sysrc` cannot tell a value the admin set from a base system default. It sources `/etc/defaults/rc.conf` whatever `-f` names, so an unset variable reads back as its default with exit 0: `sysrc -f /etc/rc.conf -n syslogd_flags` returns `-s` on a host whose rc.conf never mentions it. To learn what a file itself sets, read the file; see `rc_conf_get` in `provision/host.sh`. `sysrc` is still how to write.
- Swapping one command for another (`grep` for `sysrc`, say) changes more than syntax. Confirm which files the replacement reads and what it returns when the value is absent.

## Comments

- Self-documenting code beats comments.
- Keep only WHY comments — a hidden constraint, an invariant, a workaround for a specific bug, or an RFC citation that explains otherwise-surprising behavior.
- Delete WHAT comments that restate the code, and comments that narrate history or audit findings.
- If a rename makes a comment redundant, delete it.
- Terse: a line beats a paragraph. When cases multiply (routes by recipient and sender, say), write one table.
- No narration and no past tense: no "was", "used to", or the story of the bug.
- "This, not that" is redundant. Say what it is.
- A test's name states its intent. Don't repeat it in a comment.

## Testing

- Empirical Reproduction: For bug fixes, first create a failing test case.
- Coverage: Every new feature should have a corresponding test file with high coverage.
- Stubs mirror the real command's exit status, not just its stdout. A stub that always succeeds hides the `set -e` abort the real command would cause.
- bats disables errexit for anything under `run`. To exercise a `set -e` path, call the function in a `( set -e; ... )` subshell.
- Verify a new test fails without the fix. A test written against a stub can pass for reasons the real code never gets to.

## Tooling Commands

```bash
# Run all tests
./test/run.sh

# Run a single bats file
bats test/provision/redis.bats

# Run all provision tests
bats test/provision.bats test/provision/*.bats

# Run coverage (requires kcov; runs on ubuntu-latest in CI)
sh ./test/coverage.sh
```

## Architecture

### Entry Point and Initialization

`mail-toaster.sh` is the central library. It defines all jail lifecycle functions (`create_staged_fs`, `start_staged_jail`, `promote_staged_jail`, `stage_pkg_install`, `stage_exec`, etc.) and calls `mt6_init` at load time — unless `MT6_TEST_ENV=1`, which skips initialization. This guard is what makes unit testing possible.

`mt6_init` sources five include files in order: `util`, `config`, `zfs`, `jail`, `network`. It then loads `mail-toaster.conf` (user configuration, not checked in).

### Include Files (`include/`)

Reusable helpers sourced by provision scripts via `mt6-include`:
- `config.sh` — `mt6_defaults()` sets all default env vars (`JAIL_NET_PREFIX`, `ZFS_VOL`, `TOASTER_*`, etc.)
- `zfs.sh` — ZFS dataset/snapshot operations
- `jail.sh` — jail IP assignment, conf generation, pf rules
- `network.sh` — `get_random_ip6net`, IP utilities
- `util.sh` — `store_config`, `store_exec`, `get_random_pass`, `dec_to_hex`, `reverse_list`
- `nginx.sh` — `contains()`, `configure_nginx_server_d()`
- `linux.sh` — `configure_apt_sources()`, linuxulator setup
- `mysql.sh`, `php.sh`, `mta.sh`, `user.sh`, `shell.sh`, `editor.sh`, `vpopmail.sh`, `djb.sh`, `mua.sh`

### Provision Scripts (`provision/`)

Each `provision/<name>.sh` follows a rigid structure:
1. `. mail-toaster.sh || exit`
2. Export three required vars: `JAIL_START_EXTRA`, `JAIL_CONF_EXTRA`, `JAIL_FSTAB`
3. Define `install_<name>()`, `configure_<name>()` (optional), `start_<name>()`, `test_<name>()`
4. Execute block at bottom: `base_snapshot_exists || exit; create_staged_fs <name>; start_staged_jail <name>; install_<name>; ...; promote_staged_jail <name>`

`provision/skel.sh` is the canonical template for new jail provisioners.

Special scripts excluded from structural checks: `base.sh` (creates the base ZFS snapshot) and `bhyve-ubuntu.sh` (provisions a bhyve VM). Scripts without persistent services (no `start_` needed): `certbot.sh`, `host.sh`, `letsencrypt.sh`.

### Test Structure

```
test/
  *.bats                  # top-level: mail-toaster.sh and include.sh integration tests
  provision.bats          # structural grep-based checks across all 70+ provision scripts
  include/*.bats          # per-include-file unit tests
  provision/*.bats        # per-provision-script functional tests
  provision/helper.bash   # shared provision test setup: stubs on PATH, provision_fns, provision_run
  provision/stubs/        # stub executables injected via PATH for provision tests
    mail-toaster.sh       # comprehensive stub: all infrastructure functions as no-ops
    chown                 # no-op stub (non-root CI can't chown)
  test_helper/            # bats-support and bats-assert libraries
  coverage.sh             # runs kcov over test/*.bats and test/include/*.bats
```

### Testing Provision Scripts

Provision scripts source `mail-toaster.sh` with no path (`. mail-toaster.sh`), so the shell searches `$PATH`. `test/provision/helper.bash` puts `test/provision/stubs/` first on `$PATH`, sets `MT6_TEST_ENV=1`, and loads the assertions. Every provision test loads it rather than repeating that setup:

```bash
setup() {
  load helper
  export STAGE_MNT="$BATS_TEST_TMPDIR/stage"
  provision_fns redis          # function definitions only, execution block stripped
}
```

`provision_fns <name> [<first command of the execution block>]` defaults to `base_snapshot_exists`. `provision_run <name>` sources the whole script, execution block included; call it once in `setup_file` and have tests read what it produced.

The stub defines all FreeBSD-specific functions as no-ops. Because the execution block runs at source time, any files accessed during `install_*` (e.g., config files that `sed` will edit) must be pre-created in `$STAGE_MNT` before `provision_run`.

Where a test goes:
- A function's tests live in the file mirroring the file that defines it: `include/network.sh` → `test/include/network.bats`. `test/mail-toaster.bats` is for functions in `mail-toaster.sh`.
- An invariant every provision script shares (exports, lifecycle functions defined, permissions) is one check in `test/provision.bats` across `provision/*.sh`, not a copy in each `test/provision/<name>.bats`.
- bats traps DEBUG, so every command and subshell in a test costs extra. Build shared fixtures once in `setup_file`, and keep `JAIL_ORDERED_LIST` short when a test looks up jail IPs.

### CI

Two GitHub Actions workflows:
- `ci.yml`: runs ShellCheck (`-s bash`, several exclusions), BATS (`test/*.bats` and `test/include/*.bats`), and a FreeBSD VM smoke test (`./test/config.sh` + sourcing `mail-toaster.sh`).
- `coverage.yml`: installs kcov, runs `test/coverage.sh`, and uploads to Codecov and Qlty.

### Jail Networking

Jails use a private IPv4 subnet (`172.16.15.0/19` by default). Each jail's IP is determined by its position in `JAIL_ORDERED_LIST` (defined in `include/config.sh`). Position 1 = `.1`, position 4 (mysql) = `.4`, etc. IPv6 uses a ULA prefix generated by `get_random_ip6net`.
