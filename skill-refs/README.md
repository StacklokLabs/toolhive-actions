# Check Skill References Action

Check that the code in your skills refers to things that exist in your repository: backticked paths, `task` targets and GitHub workflows. Skills that live next to the code they describe go stale when files move, tasks are renamed or workflows are deleted, and nothing else notices.

This action covers only references that depend on the repository. Rules that hold for every skill, such as broken Markdown links, references that leave the skill directory, and scripts run without an interpreter, are checked by `thv skill validate` ([`skill-validate`](../skill-validate/README.md), ToolHive v0.67.0 or later).

The action needs no ToolHive installation: it reads files with `awk`, `jq` and `yq`, which are preinstalled on GitHub-hosted runners. It never executes repository content.

## What is checked

The action reads only code: inline code spans, and fenced blocks tagged `bash`, `sh`, `shell`, `zsh` or `console` or left untagged. A code span can wrap onto the next lines of its paragraph, and in a table row `\|` is a pipe. Fences can be indented any amount, as they are inside list items, or open on a list item's own line. Files with CRLF line endings are read the same way. Prose, frontmatter and fences in other languages are skipped. In `console` fences, only lines starting with `$ ` are commands, together with the lines that continue one after a `\`.

It scans `SKILL.md` and every other `*.md` file in each skill, except files under `assets/`, which hold templates and examples rather than references. A symlinked skill directory is followed. A symlinked Markdown file inside a skill is skipped with a warning, because ToolHive does not allow symlinks in a skill directory.

| Rule | Finding |
|------|---------|
| `path-unresolved` | A backticked path that exists neither next to the Markdown file, in the skill, next to the skill (a sibling skill), nor under `repo-root` |
| `task-unknown` | `task <target>` for a target the repository Taskfile does not define, or defines as `internal` |
| `workflow-unknown` | `gh workflow run <workflow>`, or a `.github/workflows/<file>` path in a shell fence, for a workflow that does not exist |

### Paths

A span counts as a path when it:
- starts with `./` or `../`,
- or contains `/` and ends in a file extension that starts with a letter,
- or its first segment exists in the skill or the repository.

`application/json`, `owner/repo` and `release/v1.2.3` are therefore not paths.

The following are skipped:
- URLs, anchors, options and spans with spaces;
- `<placeholders>`, `${variables}`, `$VARIABLES`, `{templates}`;
- globs, `~` and absolute paths;
- `...` and `…`, and placeholder tokens such as `vX.Y.Z`, `NNNN` or `YYYY-MM-DD`.

`#fragment`, `::symbol` and `:line` suffixes are removed before resolving.

### Taskfile targets

The root Taskfile (`Taskfile.yml`, `Taskfile.yaml`, `Taskfile.dist.yml`, … in `repo-root`) is read with `yq`, never run. The action collects:
- the root Taskfile's tasks and their aliases, with wildcard tasks such as `release:*` matching as patterns;
- tasks from local `includes` one level deep, resolved as Task does: as `<namespace>:<task>` and under namespace aliases, with an included `default` task also running as the bare `<namespace>`; with `flatten: true`, only as `<task>`.

Tasks marked `internal: true` are reported, because Task does not run them from the command line.

Some invocations are never flagged:
- tasks in a remote, templated or missing include, because they can't be resolved; when such an include is flattened, no `task` target is checked;
- tasks in an include's own includes, which are not read: `<namespace>:<sub>:…`, or any task under `<namespace>` when the nested include is flattened;
- `task --dir …` and `task --taskfile …`, which use another Taskfile, and `task` after a `cd` or `pushd` earlier in the same code span or fence, as in `cd web && task dev`, which runs in another directory;
- placeholders such as `task [target]`, `task TARGET` or `task …`, and `task --completion`.

Without a Taskfile, `task` isn't checked. A Taskfile or local include that doesn't parse fails the action, as it would fail Task, rather than report its tasks as undefined.

### Workflows

`gh workflow run` accepts a workflow file name or the workflow's `name:`, and both count. Runs with `-R` or `--repo` target another repository and are skipped, as are numeric workflow IDs.

A `.github/workflows/<file>.yml` or `.yaml` path counts only where a word starts, as in `cat .github/workflows/ci.yml` or `--file=./.github/workflows/ci.yml`. Words with a URL or an `@ref`, such as reusable workflows in another repository, are skipped. A skill that creates a workflow, as in `cp template.yml .github/workflows/new.yml`, is still flagged; add a `workflow:` allowlist entry for it.

## Allowlist

The allowlist suppresses findings that are correct for your repository: generated files, directories created at runtime, tasks from a remote include, workflows in another repository. Keeping them in one reviewed file keeps suppressions out of skill content, which is installed into users' agents.

```text
# Generated on demand by `task arch-graph`.
.seamline/*

# Created at runtime.
.claude/worktrees

# Tasks from the generated Taskfile include.
task:gen-*

# Workflows in the deployment repository.
workflow:deploy-*
```

- Lines are trimmed. Blank lines and lines starting with `#` are ignored.
- `task:<pattern>` matches task targets and `workflow:<pattern>` matches workflow names. Any other line matches paths.
- Patterns are bash patterns, and `*` also matches `/`, so `generated/*` covers nested files.
- A path entry matches the path as written in the skill, and the same path relative to `repo-root`. A trailing `/` is removed before matching, so allow `.claude/plans` rather than `.claude/plans/`.

By default, the action reads `<repo-root>/.skill-refs-allow` when it exists. If you set `allowlist` explicitly, the file must exist.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `paths` | Newline-delimited skill directories, or single-level glob patterns such as `skills/*` | Yes | - |
| `repo-root` | Repository root that paths, the Taskfile and `.github/workflows` are resolved against | No | `.` |
| `allowlist` | Allowlist file | No | `<repo-root>/.skill-refs-allow` if present |
| `fail` | Fail when a reference does not resolve; accepts exactly `'true'` or `'false'` | No | `false` |

`paths` follows the same rules as [`skill-validate`](../skill-validate/README.md), except that only skills are accepted. List vendored third-party skills separately, or leave them out: their examples refer to the projects they were written for, not to yours.

## Outputs

| Output | Description |
|--------|-------------|
| `findings` | Number of references that do not resolve |
| `report-file` | Path to a JSON report: `{"findings": [{"file", "line", "rule", "reference", "message"}]}` |

Each finding is a warning annotation on its file and line, and the step summary lists them all. Findings fail the action only with `fail: 'true'`. Start in warning mode, add allowlist entries for what is intentional, then turn `fail` on.

## Example

```yaml
name: Skill references

on:
  pull_request:

permissions:
  contents: read

jobs:
  refs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Check skill references
        uses: StacklokLabs/toolhive-actions/skill-refs@v0
        with:
          paths: |
            .claude/skills/*
            skills/*
```

## Platform Support

| Platform | Status |
|----------|--------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Untested |
