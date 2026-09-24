# security-sweep

Scheduled full-git-history secret scan across every repo (public and
private) under the `cadamantidis` GitHub account. Runs as
`.github/workflows/secret-sweep.yml` in this repo — a single "hub"
workflow rather than one copy per repo, so a new repo gets swept
automatically without any config change here.

## How it works

1. `scan.sh` asks `gh repo list` for every non-fork, non-archived repo
   under the account, public and private alike (auto-discovered, never a
   hardcoded list).
2. For each repo it does a **full** clone (history is the whole point, so
   no `--depth`/shallow clone) and runs `gitleaks detect` against it with
   `.gitleaks.toml`.
3. Each repo has a baseline file at `state/<owner>__<repo>.json` — the
   output of a previous gitleaks run. Passing that as `--baseline-path`
   makes gitleaks report only findings that aren't already in it, so a
   secret that's been sitting in history since before this sweep existed
   alerts exactly once, not on every run.
4. After each repo's scan, its baseline file is rewritten to the union of
   what was already known plus whatever just got found — so next run,
   today's findings are old news too.
5. Any findings not in a repo's baseline get aggregated and handed to
   `notify.sh`, which opens (or comments on, if one's already open) a
   GitHub Issue labeled `security-sweep` in **this** repo. GitHub's default
   notification settings email the repo owner on new issues and comments —
   that's the actual alert channel, no webhook or extra credential needed.

The issue body never contains a secret value — only the gitleaks rule id,
repo, file, a short commit sha, and gitleaks' own `Fingerprint` (which is
enough to relocate the exact match with a local `gitleaks` run).

## Running it

Locally (needs `gh` authenticated, plus `gitleaks`, `git`, `jq` on `PATH`):

```console
$ security-sweep/scan.sh
$ security-sweep/notify.sh   # only opens/updates an issue if scan.sh found something new
```

In CI, `.github/workflows/secret-sweep.yml` runs both on a daily schedule
and on `workflow_dispatch` (manual trigger via `gh workflow run
secret-sweep.yml`). It uses two different credentials for two different
jobs:

- The **Run sweep** step (repo discovery + cloning every repo, including
  private ones) authenticates with a repo secret named **`SWEEP_PAT`**,
  not the workflow's default `GITHUB_TOKEN`. `GITHUB_TOKEN` is scoped only
  to *this* repo and can't read or clone other repos — public repos "work"
  today anyway because public data is world-readable regardless of token
  scope, but private repos need real auth. `SWEEP_PAT` must exist as a
  repo secret for the private-repo portion of the sweep to work at all;
  **without it, the workflow will fail** the moment `scan.sh` tries to
  clone the first private repo.

  Create it as a **fine-grained personal access token**:
  - Resource owner: the account being swept (`cadamantidis`)
  - Repository access: **All repositories**
  - Permissions: **Contents — Read-only**

  Then add it as a repo secret named `SWEEP_PAT`.

- The **Notify on new findings** and **Commit updated baseline state**
  steps keep using the workflow's own `secrets.GITHUB_TOKEN` — they only
  need `issues: write` and `contents: write` on *this* repo (to open the
  alert issue and commit baseline updates), not read access to any other
  repo, so they don't need the wider-scoped PAT.

## Adding an allowlist entry

When a scan flags a genuine false positive (a test fixture, an example
token in docs, a placeholder credential), add an entry to
`[[allowlists]]` in `.gitleaks.toml` — by path, regex, or specific commit.
Prefer the narrowest allowlist that suppresses just that finding (a path
glob for a fixtures directory, not a blanket rule disable) so a real
secret landing in the same file later still gets caught.

After changing `.gitleaks.toml`, a repo's existing baseline may still
contain the now-allowlisted finding — that's harmless, it just means one
fewer thing changes on the next run.

## Resetting a baseline

Deleting a repo's `state/<owner>__<repo>.json` makes the next sweep treat
every current finding in that repo as new and alert on all of it — useful
after a real secret gets rotated and you want confirmation it's the only
one, or if a baseline file gets corrupted. This is rare; normally the
baseline files should only be touched by `scan.sh` (which commits them
back automatically in CI).
