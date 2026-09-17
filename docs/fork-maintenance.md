# Fork maintenance

Notes for anyone committing to this fork. Nothing here affects using the action
— see [glb-export.md](glb-export.md) for that.

## First thing in a new clone

```sh
scripts/install-hooks.sh
```

This is per-clone setup and a fresh clone needs it again. Run it before your
first commit.

## Publishing identity

Every commit this fork adds on top of upstream is published as
`HardByte Prototyping <dev@hardbyte-gmbh.de>`, and so is the tagger line on
every annotated `hb-` tag. Upstream's own commits keep their authors; they are
not ours to rewrite.

The rule exists because this repo is public. A personal name or address in
commit metadata is the thing being avoided, and metadata is where it hides: the
files themselves have been clean every time, while authorship, committership
and the tagger line are what actually leaked.

### What enforces it

Three layers, because no single one covers every route into the repo:

| Layer | Runs | Catches |
|---|---|---|
| `scripts/hooks/pre-commit` | before a commit object exists | the wrong identity, while it is still free to fix |
| `scripts/hooks/pre-push` | before anything leaves the clone | any non-org commit or tag in what is being pushed, including ones made elsewhere |
| `.github/workflows/hb-identity-guard.yml` | on every push and PR | a clone where nobody ran the installer, and commits made through the web UI |

The hooks are the prevention; the workflow is only detection. By the time CI
runs, the commit is already public — see below for why that matters.

All three call `scripts/check-identity.sh`, which allowlists the one accepted
identity rather than blocklisting anything. A blocklist would have to name the
addresses it rejects, writing the very thing we keep out of the repo into a
tracked file, and it would still miss an identity nobody anticipated.

### If the check fires

On a commit or a push, it is almost always a clone without the local override,
falling through to a personal global identity. Run `scripts/install-hooks.sh`.

If the bad commit already exists locally but has **not** been pushed, rewrite it
and carry on. If it has been pushed, read the next section first.

## Sanitizing something already published

A force-push does not retract it. Commits pushed to a public fork stay
reachable by SHA through the upstream repo's URL space, so the old object
survives the rewrite and anyone holding the SHA can still fetch it. Rewriting
is still worth doing — it takes the identity off every ref people actually
browse — but go in knowing it is mitigation, not erasure. Deleting and
recreating the repository is the only thing that removes the object, and that
breaks every existing pin.

The rewrite itself, over the fork's own range only:

```sh
git update-ref refs/backup/pre-sanitize "$(git rev-parse HEAD)"   # escape hatch

FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
  ORG_NAME="HardByte Prototyping"
  ORG_EMAIL="dev@hardbyte-gmbh.de"
  if [ "$GIT_AUTHOR_EMAIL" != "$ORG_EMAIL" ]; then
    export GIT_AUTHOR_NAME="$ORG_NAME";    export GIT_AUTHOR_EMAIL="$ORG_EMAIL"
  fi
  if [ "$GIT_COMMITTER_EMAIL" != "$ORG_EMAIL" ]; then
    export GIT_COMMITTER_NAME="$ORG_NAME"; export GIT_COMMITTER_EMAIL="$ORG_EMAIL"
  fi
' -- upstream/main..HEAD
```

The `upstream/main..HEAD` range is not optional: it is what keeps the rewrite
off upstream's commits.

Then check that the rewrite changed metadata and nothing else — the tree hash
either side must be identical:

```sh
git rev-parse 'refs/backup/pre-sanitize^{tree}' "HEAD^{tree}"
```

Annotated tags do not follow a rewrite. Any `hb-` tag pointing into the
rewritten range has to be deleted and recreated at the new commit, which also
gives it a fresh tagger line. Finish with `scripts/check-identity.sh`, then
force-push the branch and the tags.

Only commits from the bad one onward change SHA; anything older keeps its hash,
so pins at earlier tags survive untouched. Pins at a rewritten tag do not —
tell whoever holds them.

## Tag names

Pin tags use the `hb-` prefix. This is not only convention: upstream's
`.github/workflows/build-kicad-versions.yml` triggers on `v[0-9]*.[0-9]*`, so a
conventionally version-shaped tag pushed here kicks off a full KiCad container
image build under this account. Test any new tag name against that glob before
pushing it.

## Staying insert-only

The GLB feature only ever *inserts* lines into the files
`scripts/sync-upstream.sh` union-merges — `action.yml` and `entrypoint.sh` —
and modifies no existing upstream line in them. That is what lets the sync
resolve their conflicts unattended: two insertions competing for one anchor
always merge as "keep both".

There is exactly one deliberate exception, added 2026-09-16. `Dockerfile`'s
`FROM` is changed to the `-full` image tag, because the plain tag ships no 3D
model library and every stock component is silently dropped from STEP and GLB
output without it. `Dockerfile` is not union-merged, so the exception does not
weaken the auto-resolution: if upstream edits that line the merge conflicts and
stops for a human. What it does mean is that `git diff upstream/main HEAD` is
no longer zero-deletions, so that is not the invariant check any more — the
`REQUIRED_ONCE` markers in the sync script are, and `Dockerfile` now has one
for the `-full` tag so a hand-resolution cannot quietly restore upstream's line
and take the meshes with it.

`Dockerfile` also carries an `apt-get install webp` layer, added 2026-09-17 for
`pcb_output_image_webp`: `cwebp` is the encoder, because `kicad-cli` renders
PNG and JPEG and nothing else. That one is an insertion rather than a
modification, so it does not widen the exception above, but it gets a
`REQUIRED_ONCE` marker too — without the encoder the input fails every run,
and a merge that dropped the layer would otherwise show up only in CI.

Put new work in `glb/`, `docs/`, `scripts/` or a new workflow file rather than
in `entrypoint.sh`, `action.yml` or `README.md` where you can help it. If a
change genuinely must modify an upstream line, drop that file from
`UNION_FILES` in `scripts/sync-upstream.sh` first — auto-resolution is no
longer safe for it.
