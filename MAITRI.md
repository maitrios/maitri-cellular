# maitri cellular — Maintenance Guide

maitri cellular is a rebranded fork of [relctx/omarchy-cellular](https://github.com/relctx/omarchy-cellular) by relctx. It tracks upstream releases the same way [maitri](https://github.com/maitrios/maitri) tracks Omarchy and [maitri-mail](https://github.com/maitrios/maitri-mail) tracks omamail: an `upstream` branch holds a **rebranded** copy of each upstream release tag, and `main` is `upstream` plus maitri's deltas.

## Branches and remotes

| Ref | What it is |
|---|---|
| `main` | `upstream` merged in, plus the maitri deltas listed below. Release tags (`vX.Y.Z`) are cut here. |
| `upstream` | Each upstream release tag, merged with `-s ours`, its tree replaced by the tag's and passed through `tools/rebrand.sh --all`. Never commit to it by hand. |
| remote `relctx` | `https://github.com/relctx/omarchy-cellular.git`. Its tags are fetched into `refs/remotes/relctx/tags/*` so they never collide with maitri cellular's own `vX.Y.Z` tags; `tools/sync-upstream.sh` configures this. |

Never merge a raw upstream tag or upstream's `main` into `main`: every upstream line that says "omarchy" would conflict with the rename.

## Syncing a release

`.github/workflows/sync-upstream.yml` runs daily and on demand. It takes the newest upstream **published** GitHub release, runs `tools/sync-upstream.sh --no-merge <tag>`, pushes `upstream`, and opens or updates one pull request from `upstream` into `main` that lists the conflicts. It never merges. It needs a `SYNC_TOKEN` secret: a fine-grained token or GitHub App token on this repository with Contents, Pull requests and Workflows read/write. Workflows write is needed because a future upstream release may touch `.github/workflows`; a token-created pull request also triggers CI, which `GITHUB_TOKEN` would not.

Merge that pull request with a **merge commit**. Squash or rebase loses the ancestry the next sync uses to tell which release `upstream` already has. If it conflicts, do not use the GitHub editor (it would commit `main` into `upstream`); resolve locally:

```bash
git fetch origin
git switch -c beyer/sync-relctx-v2.1.0 origin/main
git merge origin/upstream
tools/rebrand.sh --paths <resolved files>   # in case a hunk brought the upstream brand back
tools/rebrand.sh --check
make test
```

By hand, without the workflow: `tools/sync-upstream.sh v2.1.0` advances `upstream` and merges it into the current branch; `tools/sync-upstream.sh --latest` prints the newest release `upstream` lacks.

## The rebrand

`tools/rebrand.sh` is the single source of truth. Rules run in this order on every tracked text file, skipping lines marked `rebrand:keep` and the files in `CONTENT_EXCLUDE`:

| Upstream | maitri cellular | Where |
|---|---|---|
| `[Omarchy](https://omarchy.org/)` | `[maitri](https://github.com/maitrios/maitri)` | README link |
| `https://github.com/relctx/omarchy-cellular.git` | `https://github.com/maitrios/maitri-cellular.git` | the install command |
| `Omarchy 4.0 (quattro) or newer.` at line start | `A current maitri.` | README requirements |
| plugin id `relctx.cellular` | `maitrios.cellular` | `manifest.json`, `moduleName`, `ipcTarget`, `maitri plugin enable …`, `~/.config/maitri/plugins/maitrios.cellular` |
| `Omarchy 4`, `Omarchy 4.0 (quattro)` | `maitri` | the shell generation the plugin targets |
| `OMARCHY_CELLULAR_*` | `MAITRI_CELLULAR_*` | environment variables |
| `omarchy-cellular`, `omarchy-cellular-providers` | `maitri-cellular`, `maitri-cellular-providers` | binaries, state directory |
| `omarchy-notification-send`, `omarchy-shell`, `omarchy plugin …` | `maitri-notification-send`, `maitri-shell`, `maitri plugin …` | maitri commands |
| `~/.config/omarchy/…` | `~/.config/maitri/…` | `cellular.conf`, `cellular.d/`, `shell.json`, the plugin directory |
| `an Omarchy` | `a maitri` | articles |
| `OMARCHY`, `Omarchy`, `omarchy` | `MAITRI`, `maitri`, `maitri` | everything else |

Protected tokens survive untouched: `relctx/omarchy-cellular` and `Erruviel/omarchy-wwan` (credit), `github.com/basecamp/omarchy`, `omacom/omarchy`, `omarchy.org`, the `omarchy-wwan` and `Omarchy WWAN` headers the self-migration matches in old configs, and the NetworkManager profile name `Omarchy Cellular` (the default in `${MAITRI_CELLULAR_CONN:-Omarchy Cellular}`, the README's mentions of it). Existing installs already have a `gsm` profile with that name; renaming the default would orphan it and leave two profiles competing. Paths are renamed with the same rules (`bin/omarchy-cellular` → `bin/maitri-cellular`).

`tools/rebrand.sh --check` fails on any unprotected brand token or branded path; CI, `make test` (through `tests/test_maitri.sh`) and the release workflow run it.

## What maitri drops

`DELETE_LIST` in `tools/rebrand.sh` is applied on every sync, so these never come back:

- upstream `.github/` (CI, funding)

## maitri deltas on main

Expect sync conflicts in these files; resolve toward maitri's side unless upstream changed the behaviour they wrap.

| File | Delta |
|---|---|
| `bin/maitri-cellular` (`rsrp_percent`, `read_state`) | The bars and the Signal percentage come from live RSRP (5G, else LTE; 0% at -120 dBm, 100% at -80 dBm) instead of ModemManager's `signal-quality`, which stalls on the T99W696: ModemManager logs `MBIM protocol error: NotOpened` on every extended-signal reload and serves the last cached value forever. Values outside -140…-40 dBm, such as the LTE anchor's -156, are ignored; with no valid RSRP it falls back to ModemManager's number. Once upstream carries an equivalent, resolve toward upstream and delete this row. |
| `shell/CellularPanel.qml` | Qt 6.12's QtQuick `Color` type shadows the `qs.Commons` palette singleton, so the file imports `qs.Commons as Commons` and reads `Commons.Color`. `tests/test_maitri.sh` fails on any bare `Color.` read under `shell/`, so a sync that brings one back is caught. If upstream qualifies it differently, resolve toward upstream. |
| `manifest.json` | `homepage`. |
| `README.md`, `MAITRI.md` | The maitri credit paragraph and this guide. |
| `.github/workflows/`, `tools/`, `tests/`, `Makefile` | maitri-only files. |

## Install and release

maitri cellular is an optional plugin, not part of the base install. Add it with:

```sh
maitri plugin add https://github.com/maitrios/maitri-cellular.git --enable
```

Release tags are `vX.Y.Z`, matching the synced upstream version, or `vX.Y.Z-maitri.N` for a maitri-only fix on top of it. Pushing one runs `.github/workflows/release.yml`, which checks that the tag and `manifest.json` agree, runs the rebrand check and the tests, and publishes `maitri-cellular-<version>.tar.gz` with `SHA256SUMS`.

## Moving an omarchy-cellular user to maitri cellular

Audited against the code and a live omarchy-cellular install on maitri (third-party plugin at `~/.config/maitri/plugins/relctx.cellular`). Do it while the old plugin is gone and the shell has reloaded, so nothing keeps writing to the old paths.

| omarchy-cellular state | maitri cellular | Migration |
|---|---|---|
| `~/.config/omarchy/cellular.conf` | `~/.config/maitri/cellular.conf` | Move. |
| `~/.config/omarchy/cellular.d/` (per-card APN, PIN, data plan; mode 0700) | `~/.config/maitri/cellular.d/` | Move, keeping the permissions. |
| `~/.local/state/omarchy-cellular/` (usage accounting, last-seen signal, card sync marker; mode 0700) | `~/.local/state/maitri-cellular/` | Move, keeping the permissions. |
| NetworkManager `gsm` profile `Omarchy Cellular` | same | Nothing; the name is kept. |
| `~/.config/maitri/plugins/relctx.cellular/` (third-party checkout) | `~/.config/maitri/plugins/maitrios.cellular/` | `maitri plugin remove relctx.cellular --yes`, then `maitri plugin add https://github.com/maitrios/maitri-cellular.git`. Left in place, both plugins load under different ids and poll the modem twice. |
| `~/.config/maitri/shell.json`: a bar layout entry `{"id": "relctx.cellular", …}` | `{"id": "maitrios.cellular", …}` | Rewrite the id in place and keep the entry's settings and position. Drop a second `maitrios.cellular` entry if the layout already has one. |
| `~/.local/bin/omarchy-cellular` (optional symlink) | `~/.local/bin/maitri-cellular` | Delete the old link and, if wanted, `ln -sf ~/.config/maitri/plugins/maitrios.cellular/bin/maitri-cellular ~/.local/bin/`. |
| `$XDG_RUNTIME_DIR/omarchy-cellular.*` | `$XDG_RUNTIME_DIR/maitri-cellular.*` | Nothing; runtime only, per process. |
| `OMARCHY_CELLULAR_*` variables in a shell profile or keybinding | `MAITRI_CELLULAR_*` | Rename. |

Any keybinding that calls `omarchy-cellular` must call `maitri-cellular`. The old `~/.config/omarchy/` directory can go once it is empty.

## Shell compatibility

omarchy-cellular is written against Omarchy's shell. maitri's shell is Omarchy 4.0.4's, rebranded, so newer upstream releases may reach for APIs maitri lacks. When a sync lands, load the panel in a maitri shell and check that it still renders; a missing `Style`, `Color` or `qs.Ui` member shows up as a QML error in the shell log.
