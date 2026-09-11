# Core patch definitions

| File | dsh version | Adds |
| --- | --- | --- |
| `archive-core-rc2.mjs` | `0.1.1-rc.2` | archive + restore + delete + "Archived" sidebar section |
| `archive-core-0.1.5.mjs` | `0.1.5-rc.1` | restore + delete + "Archived" sidebar section (archive already upstream) |

## Where it came from

Core feature (skin styling intentionally excluded) merged from
[gavinlee9051/dsh-modern-skin](https://github.com/gavinlee9051/dsh-modern-skin).
The 0.1.1-rc.2 variant is a direct port of its `patches/archive-core.mjs`; the
0.1.5-rc.1 variant is a re-port onto the restructured 0.1.5 packages (upstream
0.1.5 already ships `archiveSession` and the `archivedSessionIds` registry set).

## How it is applied

Never by hand on this repo. Linux: `../patch-archive.sh` (called by `run.sh` on
every start). Windows: `win/dsh.ps1` `Apply-ArchivePatch`. Both:

1. pick the patch matching `dsh --version` from a version table; any other
   version is **skipped with a note** (the anchors change with every dsh
   release, so applying to an unknown version would half-edit the core);
2. skip when the version's marker is already present (idempotent);
3. otherwise run: `node <patch> --root <global>/@deepseek-ai/dsh/node_modules/@deepseek-ai`

The 0.1.5 patch is a set of exact-match hunks (pristine → patched). A hunk that
does not match fails loud instead of corrupting a file. It edits the workspace
registry, the jsonl persistence backend (physical log deletion), the
`archiveSession` Remote verb (an `op` discriminator for `unarchive`/`delete`),
the client workspace service, and the sidebar UI.

## Adding a new dsh version

1. Re-validate/re-port the hunks against the new compiled files.
2. Regenerate the patch (see the temp generator approach used for 0.1.5).
3. Add the version to the tables in `patch-archive.sh` and `win/dsh.ps1`.

## Revert

`npm install -g @deepseek-ai/dsh` restores the official core; the next start
re-applies automatically. To remove the feature permanently, also delete the
patch files and the wrapper hooks.
