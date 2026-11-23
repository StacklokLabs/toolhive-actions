# Publish ToolHive Skills and AI Plugins Action

Validate, build and push every skill and AI-tool plugin in a repository as signed OCI artifacts with [ToolHive](https://github.com/stacklok/toolhive), in one step. Use it in a release workflow of a repository that keeps many skills side by side, instead of one [`skill-build`](../skill-build/README.md) step per skill.

> [!WARNING]
> Run this action with `push: 'true'` only on trusted events, after code is merged or released. Pushing signs every artifact with the job's GitHub identity. If pull-request code could reach this step, it could publish signed artifacts under your name. The action enforces this itself: with `push: 'true'` it fails unless the event is `push`, `release`, `workflow_dispatch` or `schedule`. Never call it from `pull_request_target` or `workflow_run` workflows.

## How it works

1. **Discover.**
   - Every immediate subdirectory of `root` with a `SKILL.md` is a skill.
   - With `plugins-root` set, every immediate subdirectory of it with `.claude-plugin/plugin.json` is an AI-tool plugin.
   - Subdirectories without the marker file are skipped with a warning, and loose files are ignored. Hidden subdirectories are never published; one that has the marker file gets a warning.
   - A root without any skill or plugin fails the action.
2. **Validate** every directory, with the same checks and annotations as [`skill-validate`](../skill-validate/README.md). Any error stops the action before anything is built.
3. **Build** every directory once per tag, as `<prefix>/<directory name>:<tag>`. Any failed build stops the action before anything is pushed.
4. **Push** every reference, when `push` is `'true'`, one tag at a time: the first tag for every directory, then the second, and so on. List floating tags such as `latest` last, so they move only after the release tag is published everywhere.

Builds are reproducible: an unchanged skill gets the same digest under every tag and on every release. Consumers that pin digests in `toolhive.lock.yaml` therefore see an update only for skills that actually changed.

## Prerequisites

- ToolHive CLI v0.48.0 or later (use the [install action](../install/README.md)). With `push: 'true'`, the action checks this before building, because older releases don't sign every push. v0.67.0 or later adds line-level validation annotations.
- `jq`, which is preinstalled on GitHub-hosted runners.
- For pushing:
  - Registry login before this action, for example with [docker/login-action](https://github.com/docker/login-action).
  - `id-token: write` on the job, so ToolHive can sign keylessly with the job's OIDC identity. No signing key is stored in secrets. Without the permission, the action fails before building, instead of building everything and then failing at the first push.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `root` | Directory whose immediate subdirectories are skills | No | `skills` |
| `plugins-root` | Directory whose immediate subdirectories are AI-tool plugins | No | - |
| `registry-prefix` | OCI repository prefix for skills, for example `ghcr.io/org/repo/skills` | Yes | - |
| `plugins-registry-prefix` | OCI repository prefix for AI-tool plugins | No | `registry-prefix` |
| `tags` | Newline-delimited plain tags applied to every skill and plugin, for example `v1.2.0` and `latest` | Yes | - |
| `push` | Push every built artifact; accepts exactly `'true'` or `'false'` | No | `false` |
| `validate` | Validate every directory before building; accepts exactly `'true'` or `'false'`, and an empty value is rejected | No | `true` |

- **Prefixes** must be lowercase, include a registry and a path, and have no tag, digest or trailing `/`. GitHub owner and repository names can contain capitals, but OCI paths can't, so lowercase `github.repository` yourself before passing it.
- **Directory names** become the last part of the OCI repository path, so they must be lowercase letters and digits separated by `.`, `_`, `__` or `-`. The action fails on any other name before building. The `root` and `plugins-root` paths must not contain a tab or line break.
- **Shared prefix:** when skills and plugins share a prefix, a skill and a plugin with the same directory name would overwrite each other, so the action fails before building. Set `plugins-registry-prefix` to keep them apart.
- **`tags`** entries are trimmed, and blank lines are ignored. Each must be a plain OCI tag (`[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}`), not a full reference. Duplicates are rejected.

## Outputs

| Output | Description |
|--------|-------------|
| `references` | Newline-delimited references that were pushed and signed, or built when `push` is `'false'` |
| `references-json` | The references in `references` by type and directory name, for example `{"skills": {"deploy": ["ghcr.io/org/repo/skills/deploy:v1.2.0", …]}, "plugins": {}}`. Both keys are always present |

## When a push fails

Registries have no transactions, so a push can fail after earlier references were published. The action stops at the first failed push and names it in an error. The outputs list only references that were pushed **and signed**.

ToolHive uploads a reference before it signs it. If signing fails, for example because the signing service is unreachable, the failed tag may already be in the registry **without a signature**. The step summary marks that reference. Consumers that verify signatures reject it, but anyone who pulls the tag without verifying gets unsigned content.

To recover, rerun the job. Builds are reproducible, so every reference is pushed again with the same digest and signed. Don't rerun it once a newer release has published, because that would move floating tags such as `latest` back to the older release; delete the failed tag instead. The `concurrency` group in the example below keeps two releases from publishing at the same time.

## Examples

### Publish on release

```yaml
name: Publish skills

on:
  release:
    types: [published]

concurrency:
  group: publish-skills
  cancel-in-progress: false

jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    steps:
      - uses: actions/checkout@v6

      - uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: v0.67.0

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Lowercase the repository name
        id: repo
        env:
          REPOSITORY: ${{ github.repository }}
        run: echo "name=${REPOSITORY,,}" >> "$GITHUB_OUTPUT"

      - name: Publish skills and plugins
        id: publish
        uses: StacklokLabs/toolhive-actions/skills-publish@v0
        with:
          root: skills
          plugins-root: plugins
          registry-prefix: ghcr.io/${{ steps.repo.outputs.name }}/skills
          plugins-registry-prefix: ghcr.io/${{ steps.repo.outputs.name }}/plugins
          tags: |
            ${{ github.event.release.tag_name }}
            latest
          push: 'true'
```

### Build-only check on pull requests

With `push: 'false'` the action runs on any event, so pull requests can check that everything validates and builds before release. No registry login or `id-token` is needed.

```yaml
- name: Check skills build
  uses: StacklokLabs/toolhive-actions/skills-publish@v0
  with:
    registry-prefix: ghcr.io/example/skills
    tags: pr-check
```

## Platform Support

| Platform | Status |
|----------|--------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Untested |

Building and pushing doesn't need a container runtime. With `push: 'false'`, the action reuses a ToolHive API server reachable at `TOOLHIVE_API_URL` (default `http://127.0.0.1:8080`) whose health check answers 204 or 503; otherwise it starts one on a random loopback port. With `push: 'true'`, it always starts its own, because pushing sends the job's OIDC token to that server. It stops only a server it started.
