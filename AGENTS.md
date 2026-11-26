# Agent working contract

The existing estate Git template installs pre-commit, pre-push, commit-msg and
prepare-commit-msg entrypoints in new agent clones and initializations. Linked
worktrees share their repository's hook directory. Checks run at ordinary Git
events; no session-start setup is needed. Pre-commit installs and caches managed
hook environments when first used.

For an existing checkout missing its native hooks, install them once from its
root:

```sh
pre-commit validate-config .pre-commit-config.yaml
pre-commit install --hook-type pre-commit --hook-type pre-push \
  --hook-type commit-msg --hook-type prepare-commit-msg
```

Preserve custom hooks and `core.hooksPath`; integrate their owner rather than
unsetting or overwriting it. Native hook installation does not install system
binaries. Existing host provisioning owns them, including Vale for prose checks;
the established Homebrew declaration supplies Vale through normal package
verification. Repository-native setup owns project dependencies and required files. Missing
prerequisites must fail clearly through the applicable hook or project command.
Do not run project tests merely to install hooks, or rerun installation each
session. `DOTTY_CHECKOUT` selects maintained reviewed source for shared commands.

Use the native hook stages and repository commands. Do not bypass checks with
`--no-verify`, `SKIP`, altered hook paths, or disabled scanners. Correct the finding
and retry. Keep staged-content, commit-message and outgoing-history scans active;
never expose scanner findings containing confidential content. Before every PR create or body edit, validate the exact body file with
`python3 "$DOTTY_CHECKOUT/.github/scripts/pr-body-check.py" --template .github/pull_request_template.md --body-file <body-file>`
(or `--body-file -` for stdin). Publish that same file with `gh pr create --body-file`
or `gh pr edit --body-file`. This validates
structure; retain applicable content/confidentiality scanning too.

Finish the candidate and relevant local checks before publication. For a new PR,
push successfully, then create it once with the complete title and validated
body. Do not publish a placeholder and immediately replace it, or edit
descriptions just to add CI progress or run links visible on GitHub.

For an existing PR, finish the local changes and prepare any necessary description
update before pushing. Identify the outgoing commit and only checks already
completed; do not claim a future push or hook result. Validate and scan the exact
body file as above. After the normal push succeeds, publish the necessary edit
once, immediately, before polling CI or drafting further prose. Combine title and
body changes in that edit. If the push fails, resolve it and revalidate any changed
candidate or body before publication. Read back the final head, title and body,
then follow CI and Margot through completion.

A pull request is not finished when it is opened. Its checks, Margot's review and
the operator's comments land on the pull request, so read them there until it
merges or closes:

```sh
gh pr checks <number> --repo <owner>/<repo>
gh pr view <number> --repo <owner>/<repo> --json state,reviews,comments,statusCheckRollup
```

A failed check or a review that asks for changes is the author's to resolve: fix
it and push, or answer in the thread. Margot rates each pull request. Once the
required checks pass, Ollie merges a LOW one without the operator; a MEDIUM or
HIGH one waits for the operator's `/land` comment, and her `/revisit` comment
asks Margot to review again. These commands work for any agent. Some agents are
also told when something lands: a Claude Code session is prompted to start a
watch after `gh pr create`, which covers Cyrus's sessions on calcifer too, and
Ollie receives GitHub's events on its own channel.

Keep scope, risk and verification claims accurate for the published head. A push
and a description edit are separate GitHub events; a prompt edit gives native
cancellation an earlier opportunity to stop superseded work but cannot guarantee
zero wasted runner time. Preserve description-triggered scanning, classification
and review, and the existing cancellation behavior.

Test changed behavior through its real interface using the narrowest relevant
existing suite. Do not add implementation-mirroring assertions, test-count quotas
or a new fleet suite. A new regression assertion needs a meaningful negative
control or red/green result; invalid imports or broken fixtures do not count.
Fixture repositories must clear inherited Git routing so tests cannot mutate the
caller's object store. Distinguish source tests from actual installed-agent proof.

## home-assistant

The configuration of the house's Home Assistant: one live instance on a
Raspberry Pi 5 running Home Assistant OS. The repository's working tree is the
Pi's live `/config`, so a change there is live the moment it is made; this
repository is its record and its git backup. It is public.

### Setup

Clone it and use the native hooks above. On the Pi the same hooks run in the
Terminal & SSH add-on: `tools/install-hooks.sh` sets them up, and every commit
or push there starts with `. /config/tools/pi-hook-env.sh`, because an SSH
command loads no shell profile. The README's "Checks on the Pi" says what
provides each piece.

### Build / Test

There is no build. Commit and push run the native hooks. CI runs the shared
estate checks and, for a functional change, Home Assistant's own configuration
check in a production-matched Core container (`tools/ha-ci.Dockerfile`), with
the two interface tests in `tests/` beside it. When Home Assistant Core is
updated, move the Core pin in `tools/ha-ci.Dockerfile` in the same change.

### Conventions

- Change the house's configuration on the Pi, through Home Assistant's UI or
  its MCP server, or in files over SSH, then record it from the Pi. Tooling and
  CI changes can be made from a clone; they reach the Pi only when its checkout
  is brought level with the default branch by `tools/pi-sync.sh`, run on the Pi
  after a merge. It stops without changing anything if the default branch
  changes a file the Pi changed, or one only the Pi has, and lists the files
  Home Assistant must reload.
- Home Assistant writes `automations.yaml`, `scripts.yaml`, `scene.yaml` and
  `.storage/*` itself. The hooks accept the style Home Assistant writes, and
  the end-of-file and whitespace fixers leave `.storage/` alone; edit these
  files through Home Assistant rather than by reformatting.
- Home Assistant regenerates `.cache/` and `json/*.json`; they are not tracked.
- Stage files by path, never `git add -A`: the live tree always carries runtime
  changes that must not be committed in bulk.
- Never rewrite or force-push the default branch: the running instance sits on
  it.
- Sessions commit and publish as lexijamesesq. Remy, the house's agent,
  publishes only through its own GitHub App. Nothing is committed as the Pi
  itself.
