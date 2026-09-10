# Build ToolHive AI Plugin Action

Build and optionally push an AI-tool plugin with [ToolHive](https://github.com/stacklok/toolhive) as an OCI artifact. AI-tool plugins package extensions for tools such as Claude Code or Codex; they are not ToolHive plugins. Unlike skills, which primarily package reusable agent instructions and knowledge, an AI-tool plugin can bundle tool-specific commands, agents, hooks, and related resources. Unlike an MCP server, it is packaged content rather than a service run and managed by ToolHive.

## Prerequisites

- ToolHive CLI v0.48.0 or later (use the [install action](../install/README.md))
- For publishing, authentication to the target OCI registry

## Plugin Layout

The input directory name must match the plugin's manifest `name`. It must contain the Claude plugin manifest at the exact path `.claude-plugin/plugin.json`:

```text
test-plugin/
├── .claude-plugin/
│   └── plugin.json
├── commands/          # Optional tool-specific content
├── agents/            # Optional tool-specific content
└── hooks/             # Optional tool-specific content
```

A minimal manifest is:

```json
{
  "name": "test-plugin",
  "description": "An example AI-tool plugin",
  "version": "0.1.0",
  "author": {
    "name": "Example Organization"
  }
}
```

The action checks that the directory and manifest exist, then runs `thv ai-plugin validate` before building.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `path` | Path to the AI-tool plugin directory containing `.claude-plugin/plugin.json` | Yes | - |
| `tags` | Newline-delimited complete OCI references | No | ToolHive default |
| `push` | Push every built artifact to its OCI registry; accepts exactly `'true'` or `'false'` | No | `false` |

`tags` entries are trimmed, blank lines are ignored, input order is preserved, and duplicate trimmed references are rejected. With no nonblank references, the action builds once and uses ToolHive's default reference. With multiple references, it runs one build per reference; because these are separate builds, their digests are not guaranteed to match.

## Outputs

| Output | Description |
|--------|-------------|
| `reference` | First OCI reference built by the action |
| `references` | Newline-delimited references for all builds, in input order |

## Examples

### Build Only

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: StacklokLabs/toolhive-actions/install@v0
    with:
      version: v0.48.0

  - name: Build plugin
    id: plugin
    uses: StacklokLabs/toolhive-actions/ai-plugin-build@v0
    with:
      path: ./test-plugin
```

### Build Multiple References

Partial workflow continuation (after the checkout and ToolHive install steps shown above):

```yaml
- name: Build versioned plugin artifacts
  id: plugin
  uses: StacklokLabs/toolhive-actions/ai-plugin-build@v0
  with:
    path: ./test-plugin
    tags: |
      ghcr.io/example/test-plugin:${{ github.sha }}
      ghcr.io/example/test-plugin:latest

- name: Show built references
  env:
    REFERENCES: ${{ steps.plugin.outputs.references }}
  run: printf '%s\n' "$REFERENCES"
```

### Publish Signed Artifacts to GHCR

ToolHive pushes signed artifacts by default. GitHub's OIDC token enables keyless signing, so no long-lived signing key is stored in repository secrets. The job needs source access, GHCR write access, and permission to request that OIDC identity token:

```yaml
jobs:
  publish:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: v0.48.0

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and publish signed plugin
        uses: StacklokLabs/toolhive-actions/ai-plugin-build@v0
        with:
          path: ./test-plugin
          tags: |
            ghcr.io/${{ github.repository_owner }}/test-plugin:${{ github.ref_name }}
            ghcr.io/${{ github.repository_owner }}/test-plugin:latest
          push: 'true'
```

The action deliberately relies on ToolHive's signed push default and does not expose unsigned or signing configuration.

## Platform Support

| Platform | Build and push |
|----------|----------------|
| Ubuntu (Linux) | Supported |
| macOS | Supported |
| Windows | Untested |

AI-tool plugin build and push package OCI artifacts and do not require an MCP server container runtime. The action reuses a reachable ToolHive API configured by `TOOLHIVE_API_URL`; otherwise it starts a loopback daemon and stops only that action-owned process.
