# Report Skill Context Budget Action

Estimate how much of an agent's context each skill uses, see how a pull request changes it, and flag skills that grow past a limit. The report lands in the step summary and, optionally, in a sticky pull request comment.

Agents load every skill's `description` in every session, load a skill's `SKILL.md` when the skill is used, and read its other files on demand. The action reports each of these:

| Column | What it measures |
|--------|------------------|
| SKILL.md tokens | Estimated tokens of `SKILL.md`, checked against `max-skill-tokens` |
| SKILL.md lines | Lines of `SKILL.md`, checked against `max-skill-lines` |
| Directory tokens | Estimated tokens of the text files in the skill directory. In a Git repository, ignored files such as dependencies and build output don't count; binary files, symlinks and submodules are skipped |
| Description tokens | Estimated tokens of the frontmatter `description`. A frontmatter that doesn't parse fails the action instead of counting as empty |

A total of all description tokens follows the table.

Token counts are **estimates**: characters ÷ 4, rounded up. Real counts depend on the model's tokenizer, but the estimate is stable, so the deltas are meaningful.

The action needs no ToolHive installation: it reads the files with `jq`, `yq` and `git`, which are preinstalled on GitHub-hosted runners.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `paths` | Newline-delimited skill directories, or single-level glob patterns such as `skills/*` | Yes | - |
| `max-skill-tokens` | Estimated token limit for each `SKILL.md` | No | `5000` |
| `max-skill-lines` | Line limit for each `SKILL.md` | No | `500` |
| `base-ref` | Commit to compare against | No | The pull request base commit |
| `fail` | Fail when a skill exceeds a limit; accepts exactly `'true'` or `'false'` | No | `false` |
| `comment` | Post or update a sticky pull request comment; accepts exactly `'true'` or `'false'` | No | `false` |
| `comment-key` | Identifies the sticky comment, so several budget reports can share a pull request | No | `default` |
| `github-token` | Token for the comment; needs `pull-requests: write` | No | `github.token` |
| `comment-author` | Login that `github-token` comments as, for example `my-app[bot]`. Needed only for a GitHub App token | No | - |

`paths` follows the same rules as [`skill-validate`](../skill-validate/README.md), except that only skills (directories with a `SKILL.md`) are accepted. Globs skip AI-tool plugins. A skill whose `SKILL.md` is a symlink fails the action, because ToolHive does not allow symlinks in a skill directory.

`max-skill-lines` overlaps with ToolHive's own warning for a `SKILL.md` over 500 lines. Use it to set a different limit for your repository.

A skill over a limit gets a warning annotation and an ❌ in the report. It fails the action only with `fail: 'true'`.

## Deltas against the base

On pull requests, each value shows its change against the base commit, for example `1250 (+80)`. A skill missing from the base is marked `(new)`. A skill that a glob in `paths` matched at the base commit but that is gone now is listed as deleted, with negative deltas, so removals lower the totals too.

The base commit must be in the checkout. The default `actions/checkout` fetches a single commit; on `pull_request` it checks out a merge commit whose first parent is the base, so `fetch-depth: 2` is enough. Without the base commit, the action warns and reports values without deltas; it never fetches. Outside pull requests `base-ref` is empty, so there are no deltas.

Base files are read through the repository's checkout filters, such as `eol=crlf` in `.gitattributes`, so they compare byte for byte with the checked-out files.

If you check out the pull request head instead (`ref: ${{ github.event.pull_request.head.sha }}`), deltas against the base tip also include commits that landed on the base branch after the branch point, as negative changes to skills the pull request didn't touch. Pass the merge base as `base-ref` in that case.

## Sticky comment

With `comment: 'true'`, the action keeps one comment per pull request, found by the hidden marker `<!-- toolhive-skill-budget:<comment-key> -->` and written by the same account as the token, so it never overwrites someone else's comment. A personal access token looks its account up, and the default `github.token` comments as `github-actions[bot]`. A GitHub App token can't look itself up, so set `comment-author` to the app's bot login; without it, the comment is skipped with a warning rather than posted again on every run.
- It posts or updates the comment when a value changed or a limit is exceeded.
- When nothing changed against the base, it updates an existing comment to "No budget changes" and posts nothing new.
- When the base commit is not in the checkout, or `base-ref` is empty, there are no deltas. It then updates an existing comment with the current numbers and a note, rather than claiming nothing changed, and posts a new one only when a limit is exceeded.

The comment is skipped, with a notice:
- outside `pull_request` events,
- on pull requests from forks, whose token is read-only,
- when `github-token` is empty.

A token without permission produces a warning, not a failure.

> [!WARNING]
> Don't run this action from `pull_request_target` to comment on fork pull requests. That event gives a write token to a job that checks out untrusted pull request content.

## Outputs

| Output | Description |
|--------|-------------|
| `report-markdown` | The report as Markdown |
| `report-file` | Path to the report as JSON |
| `over-budget` | `'true'` when a skill exceeds a limit |
| `comment-id` | ID of the sticky comment that was posted or updated; empty when none was |

`report-markdown` contains text from the pull request (paths and counts). Pass it to later steps through `env:`, never inline as `${{ }}` in `run:`, to avoid script injection.

## Examples

### Comment on pull requests

```yaml
name: Skill budget

on:
  pull_request:
    paths:
      - 'skills/**'

permissions:
  contents: read
  pull-requests: write

jobs:
  budget:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 2

      - name: Report skill budget
        uses: StacklokLabs/toolhive-actions/skill-budget@v0
        with:
          paths: skills/*
          comment: 'true'
```

### Use the report in a later step

```yaml
- name: Report skill budget
  id: budget
  uses: StacklokLabs/toolhive-actions/skill-budget@v0
  with:
    paths: skills/*

- name: Save the report
  env:
    REPORT_MARKDOWN: ${{ steps.budget.outputs.report-markdown }}
  run: printf '%s\n' "$REPORT_MARKDOWN" > budget.md
```

## Platform Support

| Platform | Status |
|----------|--------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Untested |
