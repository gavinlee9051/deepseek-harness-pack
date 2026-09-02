# Core patch definitions

| File | Purpose |
| --- | --- |
| `archive-core-rc2.mjs` | Adds the **session archive** feature (archive / restore / delete sessions, "Archived" sidebar section) to dsh. Replaces anchors in compiled files of several dsh core packages under `@deepseek-ai/dsh/node_modules/@deepseek-ai/*`. |

## Where it came from

Core feature (skin styling intentionally excluded) merged from
[gavinlee9051/dsh-modern-skin](https://github.com/gavinlee9051/dsh-modern-skin)
`patches/archive-core.mjs`, adapted to `dsh 0.1.1-rc.2` because upstream's anchors
assume a base that already ships runtime `unarchiveSession`/`deleteSession` methods.

## How it is applied

Never by hand on this repo. Linux: `../patch-archive.sh` (called by `run.sh` on
every start). Windows: `win/dsh.ps1` `Apply-ArchivePatch`. Both:

1. skip when the archive marker is already present (idempotent);
2. skip with a note when `dsh --version` differs from the pinned supported version
   (`0.1.1-rc.2`) — the anchors change with every dsh release, so applying to an
   unknown version would half-edit the core;
3. otherwise run: `node archive-core-rc2.mjs --root <global>/@deepseek-ai/dsh/node_modules/@deepseek-ai`

When a new dsh version ships, re-validate the anchors against the new files,
bump `ARCHIVE_SUPPORTED` / `$ArchiveSupportedVersion` here and in the two wrapper
scripts, then regenerate this patch from the upstream skin repo.

## Revert

`npm install -g @deepseek-ai/dsh` restores the official core; the next start
re-applies automatically. To remove the feature permanently, also delete this
patch file and the wrapper hooks.
