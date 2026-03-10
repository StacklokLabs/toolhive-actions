# Build ToolHive Skill Action

Build and optionally push a [ToolHive](https://github.com/stacklok/toolhive) skill as an OCI artifact. Skills are portable knowledge packages for AI agents following the [Agent Skills Specification](https://agentskills.io/specification).

## Features

- Build a skill from a local directory containing a `SKILL.md`
- Tag the resulting OCI artifact with a custom reference
- Optionally push to any OCI-compatible registry (ghcr.io, Docker Hub, etc.)
- Validates skill structure before building

## Prerequisites

- ToolHive CLI must be installed (use the [install action](../install/README.md))
- For pushing: registry credentials must be configured before this action runs (e.g., via [docker/login-action](https://github.com/docker/login-action))

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `path` | Path to the skill directory containing `SKILL.md` | Yes | - |
| `tag` | OCI tag for the built artifact (e.g., `ghcr.io/org/skill-name:v1.0.0`) | No | Skill name from `SKILL.md` |
| `push` | Push the artifact to a remote OCI registry | No | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `reference` | OCI reference of the built skill artifact |

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

```yaml
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
      tag: ghcr.io/${{ github.repository_owner }}/my-skill:latest
      push: 'true'
```

### Build and Push with Semantic Versioning

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: stacklok/toolhive-actions/install@v0

  - uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }}

  - name: Build and push skill
    uses: stacklok/toolhive-actions/skill-build@v0
    with:
      path: ./skills/my-skill
      tag: ghcr.io/${{ github.repository_owner }}/my-skill:${{ github.ref_name }}
      push: 'true'
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

- The action validates the skill directory structure before building
- No registry credentials are handled by this action — use a dedicated login action (e.g., `docker/login-action`) to configure credentials before pushing
- The ToolHive daemon is started on a random available port and stopped after the action completes

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

### Push fails with authentication error

Ensure you have logged in to your registry before running this action. For example:

```yaml
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```
