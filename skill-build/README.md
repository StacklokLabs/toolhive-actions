# Build ToolHive Skill Action

Build and optionally push a [ToolHive](https://github.com/stacklok/toolhive) skill as an OCI artifact. Skills are portable knowledge packages for AI agents following the [Agent Skills Specification](https://agentskills.io/specification).

## Features

- Build a skill from a local directory containing a `SKILL.md`
- Build one artifact for each requested OCI reference
- Optionally push every built artifact to any OCI-compatible registry (ghcr.io, Docker Hub, etc.)
- Validates the skill with `thv skill validate` and checks tag input before building

## Prerequisites

- ToolHive CLI must be installed (use the [install action](../install/README.md))
- For pushing: registry credentials must be configured before this action runs (e.g., via [docker/login-action](https://github.com/docker/login-action))

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `path` | Path to the skill directory containing `SKILL.md` | Yes | - |
| `tags` | Newline-delimited complete OCI references | No | ToolHive default (when `tag` is also omitted) |
| `tag` | **Deprecated.** One complete OCI reference; use `tags` instead | No | - |
| `push` | Push every built artifact to a remote OCI registry | No | `false` |

`tags` entries are trimmed, blank lines are ignored, and order is preserved. Duplicate references are rejected. `tag` and `tags` cannot be supplied together. When neither contains a reference, ToolHive's existing default-reference behavior is used. Because `thv skill build --tag` accepts one reference, the action performs a separate build for each explicit reference. Builds are reproducible, so every reference built from the same content has the same digest.

The deprecated `tag` input remains compatible with existing workflows and emits a GitHub Actions warning when used. Migrate a single tag like this:

```yaml
# Before
with:
  path: ./my-skill
  tag: ghcr.io/example/my-skill:v1

# After
with:
  path: ./my-skill
  tags: ghcr.io/example/my-skill:v1
```

## Outputs

| Output | Description |
|--------|-------------|
| `reference` | First OCI reference built by the action |
| `references` | Newline-delimited OCI references built by the action, in input order |

## Usage

### Build Only

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: stacklok/toolhive-actions/install@v0

  - name: Build skill
    id: build
    uses: stacklok/toolhive-actions/skill-build@v0
    with:
      path: ./my-skill
```

### Build and Push to GHCR

Pushing signs the skill keylessly with the job's OIDC token, so the job needs `id-token: write` (and `packages: write` for GHCR):

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
steps:
  - uses: actions/checkout@v4

  - uses: stacklok/toolhive-actions/install@v0

  - uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - name: Build and push skill
    id: build
    uses: stacklok/toolhive-actions/skill-build@v0
    with:
      path: ./my-skill
      tags: ghcr.io/${{ github.repository_owner }}/my-skill:latest
      push: 'true'
```

### Build and Push Multiple References

Each nonblank `tags` line must be a complete OCI reference. There is no implicit repository or registry shared between lines.

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: stacklok/toolhive-actions/install@v0

  - uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - name: Build and push versioned skill
    id: build
    uses: stacklok/toolhive-actions/skill-build@v0
    with:
      path: ./skills/my-skill
      tags: |
        ghcr.io/${{ github.repository_owner }}/my-skill:${{ github.ref_name }}
        ghcr.io/${{ github.repository_owner }}/my-skill:latest
      push: 'true'

  - name: Show built references
    env:
      REFERENCES: ${{ steps.build.outputs.references }}
    run: printf '%s\n' "$REFERENCES"
```

## Skill Directory Structure

A skill directory must contain at minimum a `SKILL.md` file with YAML frontmatter:

```
my-skill/
  SKILL.md           # Required: skill definition with frontmatter
  references/        # Optional: additional documentation
    COMMANDS.md
    EXAMPLES.md
```

Example `SKILL.md`:

```markdown
---
name: my-skill
description: "A brief description of what this skill does"
version: "0.1.0"
license: Apache-2.0
---

# My Skill

Detailed documentation and instructions for the AI agent...
```

See the [Agent Skills Specification](https://agentskills.io/specification) for the full format.

## Platform Support

| Platform | Status |
|----------|--------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Not yet tested |

## Security

- The action runs `thv skill validate` before building, so an invalid skill fails without building anything
- With `push: 'true'`, the action fails before building unless the job can request an OIDC token (`permissions: id-token: write`). ToolHive signs pushed skills keylessly with that token; without it, ToolHive would fall back to an interactive browser sign-in that cannot complete in CI
- No registry credentials are handled by this action — use a dedicated login action (e.g., `docker/login-action`) to configure credentials before pushing
- The action reuses a ToolHive daemon reachable at `TOOLHIVE_API_URL` (default `http://127.0.0.1:8080`) whose health check answers 204 or 503; otherwise it starts one on a random loopback port and stops only that action-owned process

## Troubleshooting

### "ToolHive CLI (thv) is not installed"

Add the install action before this action:

```yaml
- uses: stacklok/toolhive-actions/install@v0
```

### "SKILL.md not found"

Ensure your `path` input points to a directory containing a valid `SKILL.md` file.

### "ToolHive daemon failed to start"

Check that the ToolHive version you installed supports the `skill` command. This feature requires a recent version of ToolHive.

### "Pushing signs artifacts with the job's GitHub OIDC token"

The job pushes with `push: 'true'` but lacks permission to request an OIDC token. Add it to the job:

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
```

### Push fails with authentication error

Ensure you have logged in to your registry before running this action. For example:

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```
