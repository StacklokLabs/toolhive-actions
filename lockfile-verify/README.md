# Verify locked ToolHive content

This action verifies that committed project-scoped skills and AI-tool plugins
match `toolhive.lock.yaml`. Use it as a pull-request gate for changes to the
lock file or materialized content.

The action restores each selected resource from its pinned digest and verifies
its recorded trust policy. It then fails if the restore changes a tracked file
or creates an untracked file in the project root.

## Prerequisites

- Check out the repository before running this action.
- Install ToolHive v0.48.0 or later.
- Authenticate to private or rate-limited OCI registries before running the
  action.
- Run the action before steps that intentionally modify the Git worktree.

The `clients` input must match the clients used for the project installation.

## Verify pull requests

```yaml
name: Verify ToolHive content

on:
  pull_request:
    paths:
      - 'toolhive.lock.yaml'
      - '.claude/skills/**'
      - '.claude/plugins/**'
      - '.agents/skills/**'
      - '.agents/plugins/**'
      - '.github/workflows/verify-toolhive-content.yml'

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: latest

      - name: Authenticate to GHCR
        run: |
          echo "${{ github.token }}" | docker login ghcr.io \
            --username "${{ github.actor }}" --password-stdin

      - name: Verify locked ToolHive content
        uses: StacklokLabs/toolhive-actions/lockfile-verify@v0
        with:
          resources: all
          clients: claude-code
```

Set `clients` to the comma-separated clients recorded for your project. Use
`resources: skills` or `resources: ai-plugins` when the repository manages
only one resource type.

## Inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `resources` | Resources to verify: `skills`, `ai-plugins`, or `all` | No | `all` |
| `clients` | Comma-separated target clients, or `all` | Yes | - |
| `project-root` | Git project root containing `toolhive.lock.yaml` | No | `.` |

## Outputs

| Output | Description |
| --- | --- |
| `verified` | `true` when committed content matches the lock file |

The action checks the complete Git status below `project-root`, including
untracked files. Run it on a clean checkout before build or generation steps.

## Security behavior

ToolHive restores content from the pinned digest and enforces the trust
decision in `toolhive.lock.yaml`. Signature verification or trust-policy
failures stop the action before the Git comparison.

The action reuses a reachable daemon from `TOOLHIVE_API_URL`. Otherwise, it
starts a loopback daemon and stops only the process that it started.

## Next steps

- Add the [lock file update action](../lockfile-update/README.md) to create
  reviewable update pull requests.
