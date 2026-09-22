# Update locked ToolHive content

This action checks project-scoped ToolHive skills and AI-tool plugins for
updates. It can apply available updates so a later workflow step can open a
pull request containing the lock file and materialized content changes.

The action restores the pinned state before checking for updates. It leaves
ToolHive's signer-change and repository-change guards enabled.

## Prerequisites

- Check out the repository before running this action.
- Install ToolHive v0.48.0 or later.
- Create `toolhive.lock.yaml` by installing at least one project-scoped skill
  or AI-tool plugin.
- Authenticate to private or rate-limited OCI registries before running the
  action.

The `clients` input must match the clients used for the project installation.
CI runners cannot infer this value from installed applications.

## Open an update pull request

The following workflow checks for skill and AI-tool plugin updates every
Monday. When an update is available, it applies the update and opens a pull
request for review.

```yaml
name: Update ToolHive content

on:
  schedule:
    - cron: '0 6 * * 1'
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  update:
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

      - name: Update locked ToolHive content
        id: update
        uses: StacklokLabs/toolhive-actions/lockfile-update@v0
        with:
          resources: all
          clients: claude-code

      - name: Open pull request
        if: steps.update.outputs.updated == 'true'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          branch="toolhive-updates/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
          title="Update locked ToolHive content"

          git config user.name "github-actions[bot]"
          git config user.email \
            "41898282+github-actions[bot]@users.noreply.github.com"
          git checkout -b "$branch"
          git add -A
          git commit -m "$title"
          git push --set-upstream origin "$branch"

          gh pr create \
            --base "$GITHUB_REF_NAME" \
            --head "$branch" \
            --title "$title" \
            --body "Review the skill and AI-tool plugin content changes before merging."
```

Set `clients` to the comma-separated clients recorded for your project. Use
`resources: skills` or `resources: ai-plugins` when the repository manages
only one resource type.

The example uses `github.token` to create the pull request. GitHub does not
start another workflow from events created with this token. Use a
[GitHub App token](https://github.com/actions/create-github-app-token) for the
push and `gh pr create` when the generated pull request must start the
verification workflow immediately.

## Check without applying updates

Set `apply` to `false` to use the action as a freshness check. The action
reports available updates through its outputs without applying them.

```yaml
- name: Check locked ToolHive content
  id: check
  uses: StacklokLabs/toolhive-actions/lockfile-update@v0
  with:
    resources: all
    clients: claude-code
    apply: 'false'

- name: Fail when updates are available
  if: steps.check.outputs.updates-available == 'true'
  run: exit 1
```

## Inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `resources` | Resources to update: `skills`, `ai-plugins`, or `all` | No | `all` |
| `clients` | Comma-separated target clients, or `all` | Yes | - |
| `project-root` | Directory containing `toolhive.lock.yaml` | No | `.` |
| `apply` | Apply available updates; accepts `true` or `false` | No | `true` |

## Outputs

| Output | Description |
| --- | --- |
| `updates-available` | Whether any selected resource has an update |
| `skills-updates-available` | Whether a locked skill has an update |
| `ai-plugins-updates-available` | Whether a locked AI-tool plugin has an update |
| `updated` | Whether the action applied at least one update |
| `skills-plan-file` | Path to the skill upgrade plan in JSON format |
| `ai-plugins-plan-file` | Path to the AI-tool plugin upgrade plan in JSON format |

Plan files remain in the runner's temporary directory for later workflow
steps. The action treats ToolHive exit code `2` as an available update. Exit
codes `3` and `4` fail the action because they indicate an operational failure
or a policy guard.

## Security behavior

The action does not pass `--allow-ref-change` or `--allow-signer-change`.
ToolHive blocks an update when the artifact moves to another repository or the
recorded signer changes.

The action reuses a reachable daemon from `TOOLHIVE_API_URL`. Otherwise, it
starts a loopback daemon and stops only the process that it started.

## Next steps

- Add the [lock file verification action](../lockfile-verify/README.md) to pull
  requests that change locked content.
- Review [build ToolHive skills](../skill-build/README.md) when publishing a
  skill.
- Review [build ToolHive AI plugins](../ai-plugin-build/README.md) when
  publishing an AI-tool plugin.
