# Validate ToolHive Skills and AI Plugins Action

Validate [agent skills](https://agentskills.io/specification) and AI-tool plugins with [ToolHive](https://github.com/stacklok/toolhive), and report each problem as a GitHub annotation on the file and line it concerns. Use it as a pull-request check for repositories that author skills or plugins.

The action runs `thv skill validate` for every directory with a `SKILL.md` and `thv ai-plugin validate` for every directory with `.claude-plugin/plugin.json`. The rules come from ToolHive. This action selects the directories, collects the results, and reports them.

## Prerequisites

- ToolHive CLI v0.48.0 or later (use the [install action](../install/README.md)). v0.67.0 or later adds:
  - file and line annotations,
  - checks for broken or escaping links in `SKILL.md`,
  - checks for bundled scripts that are executed directly.
- `jq`, which is preinstalled on GitHub-hosted runners.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `paths` | Newline-delimited skill or AI-tool plugin directories, or single-level glob patterns | Yes | - |
| `fail-on-warnings` | Fail when validation reports warnings; accepts exactly `'true'` or `'false'` | No | `false` |

`paths` entries are trimmed, and blank lines are ignored. Two entries that resolve to the same directory are validated once.

- **A plain path** must be a skill or AI-tool plugin directory. Anything else fails the action.
- **A glob pattern** (`*`, `?`, `[...]`) skips matches that are neither, so `skills/*` can sit next to a `README.md`. A pattern that matches no skill or plugin directory fails the action, so a moved directory isn't silently skipped.
- **`**` is not supported.** List each level instead, for example `skills/*` and `plugins/*/skills/*`.
- **A directory with both `SKILL.md` and `.claude-plugin/plugin.json`** fails the action, because it can't be both.

## Outputs

| Output | Description |
|--------|-------------|
| `valid` | `'true'` when no directory has validation errors. Warnings, even with `fail-on-warnings`, don't change it |
| `report-file` | Path to a JSON report with the result for every directory |
| `error-count` | Total number of validation errors |
| `warning-count` | Total number of validation warnings |

The report has this shape. `findings` is present only when ToolHive v0.67.0 or later reports at least one finding for that directory:

```json
{
  "valid": true,
  "results": [
    {
      "path": "skills/deploy",
      "type": "skill",
      "valid": true,
      "errors": [],
      "warnings": ["link \"references/setup.md\" does not exist"],
      "findings": [
        {
          "severity": "warning",
          "rule": "ref-unresolved",
          "file": "SKILL.md",
          "line": 12,
          "message": "link \"references/setup.md\" does not exist"
        }
      ]
    }
  ]
}
```

`findings[].file` is relative to the validated directory. For a skill bundled in a plugin it is, for example, `skills/helper/SKILL.md`.

## Reporting

The action reports results in three places:

- **Annotations.**
  - With ToolHive v0.67.0 or later, every finding is annotated on its file and line, titled with its rule ID (for example `ref-unresolved`).
  - Older releases report only messages, so the action annotates `SKILL.md` or `.claude-plugin/plugin.json` and prints one notice suggesting an upgrade.
- **Step summary.** A table with the result for each directory, followed by every error and warning.
- **Report file.** The JSON above, for later steps.

GitHub shows at most 10 annotations of each type per step. With more findings, the step summary and the report file are the complete record.

The action validates every directory before it fails, so one run shows all problems. It fails when any directory is invalid, or when `fail-on-warnings` is `'true'` and there are warnings; warnings stay warning annotations either way.

## Examples

### Validate on pull requests

```yaml
name: Validate skills

on:
  pull_request:
    paths:
      - 'skills/**'
      - 'plugins/**'

permissions:
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: v0.67.0

      - name: Validate skills and plugins
        uses: StacklokLabs/toolhive-actions/skill-validate@v0
        with:
          paths: |
            skills/*
            plugins/*
          fail-on-warnings: 'true'
```

### Use the report in a later step

```yaml
- name: Validate skills
  id: validate
  continue-on-error: true
  uses: StacklokLabs/toolhive-actions/skill-validate@v0
  with:
    paths: skills/*

- name: List invalid skills
  env:
    REPORT_FILE: ${{ steps.validate.outputs.report-file }}
  run: jq -r '.results[] | select(.valid | not) | .path' "$REPORT_FILE"
```

## Platform Support

| Platform | Status |
|----------|--------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Untested |

Validation doesn't need a container runtime. The action reuses a ToolHive API server reachable at `TOOLHIVE_API_URL` (default `http://127.0.0.1:8080`) whose health check answers 204 or 503. Otherwise it starts one on a random loopback port and stops only that action-owned process.

## Security

The action only reads the listed directories. It needs no token and no permissions beyond `contents: read`, so it is safe to run on `pull_request` from forks.
