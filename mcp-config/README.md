# MCP Configuration Action

This GitHub Action persists MCP (Model Context Protocol) server configurations from Toolhive to a file and optionally uploads it as an artifact.

## Description

The `mcp-config` action retrieves the current MCP server configuration using the `thv list --format=mcpservers` command and saves it to a file. This is useful for:

- Backing up MCP server configurations
- Sharing configurations between workflow jobs
- Debugging and auditing MCP server setups
- Restoring configurations in subsequent workflow runs
- Filtering servers by labels for environment-specific configurations

## Prerequisites

- Toolhive (`thv`) must be installed in your workflow. Use the `stacklok/toolhive-actions/install` action first.
- MCP servers should be configured and running if you want to capture their configuration.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `output-file` | Path to the output file where MCP server configuration will be saved | No | `mcp-servers.json` |
| `artifact-name` | Name of the artifact to upload (if artifact upload is enabled) | No | `mcp-server-config` |
| `upload-artifact` | Whether to upload the configuration as a GitHub Actions artifact | No | `false` |
| `label-filter` | Label filter for MCP servers (e.g., "environment=production") | No | `` |

## Outputs

| Output | Description |
|--------|-------------|
| `config-file` | Path to the saved MCP server configuration file |
| `server-count` | Number of MCP servers in the configuration |

## Usage

### Basic Usage

```yaml
- name: Save MCP configuration
  uses: stacklok/toolhive-actions/mcp-config@main
```

### Save to Custom File

```yaml
- name: Save MCP configuration
  uses: stacklok/toolhive-actions/mcp-config@main
  with:
    output-file: .github/mcp-config.json
```

### Upload as Artifact

```yaml
- name: Save and upload MCP configuration
  uses: stacklok/toolhive-actions/mcp-config@main
  with:
    upload-artifact: 'true'
    artifact-name: 'mcp-servers-backup'
```

### Filter by Label

```yaml
- name: Save production MCP servers
  uses: stacklok/toolhive-actions/mcp-config@main
  with:
    label-filter: 'environment=production'
    output-file: prod-servers.json
```

### Complete Example with MCP Server Setup

```yaml
name: MCP Configuration Workflow

on:
  push:
    branches: [ main ]

jobs:
  setup-and-persist:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Toolhive
        uses: stacklok/toolhive-actions/install@main
      
      - name: Run Fetch MCP Server
        uses: stacklok/toolhive-actions/run-mcp-server@main
        with:
          server: fetch
      
      - name: Run GitHub MCP Server
        uses: stacklok/toolhive-actions/run-mcp-server@main
        with:
          server: github
      
      - name: Save MCP configuration
        id: persist
        uses: stacklok/toolhive-actions/mcp-config@main
        with:
          output-file: mcp-config.json
          upload-artifact: 'true'
      
      - name: Display configuration info
        run: |
          echo "Configuration saved to: ${{ steps.persist.outputs.config-file }}"
          echo "Number of servers: ${{ steps.persist.outputs.server-count }}"
          cat mcp-config.json
```

### Restore Configuration in Another Job

```yaml
jobs:
  save-config:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Toolhive
        uses: stacklok/toolhive-actions/install@main
      
      # ... setup MCP servers ...
      
      - name: Save MCP configuration
        uses: stacklok/toolhive-actions/mcp-config@main
        with:
          upload-artifact: 'true'
  
  use-config:
    needs: save-config
    runs-on: ubuntu-latest
    steps:
      - name: Download MCP configuration
        uses: actions/download-artifact@v4
        with:
          name: mcp-server-config
      
      - name: Display saved configuration
        run: |
          echo "MCP Server Configuration:"
          cat mcp-servers.json | jq .
```

### Environment-Specific Configurations

```yaml
- name: Save development servers
  uses: stacklok/toolhive-actions/mcp-config@main
  with:
    label-filter: 'env=dev'
    output-file: dev-servers.json

- name: Save production servers
  uses: stacklok/toolhive-actions/mcp-config@main
  with:
    label-filter: 'env=prod'
    output-file: prod-servers.json
    upload-artifact: 'true'
    artifact-name: 'prod-mcp-config'
```

## Configuration Format

The action saves the MCP server configuration in JSON format as returned by `thv list --format=mcpservers`. The structure typically includes:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "...",
      "args": [...],
      "env": {...},
      "transport": "stdio"
    }
  }
}
```

The exact structure depends on your Toolhive version and configured servers.

## Troubleshooting

### No MCP servers found

If the action reports no MCP servers, ensure that:
1. Toolhive is properly installed
2. MCP servers are configured and running
3. The `thv` command is in the PATH
4. If using label filters, ensure servers have the correct labels

### Invalid JSON format

If the configuration file contains invalid JSON:
1. Check your Toolhive version supports the `--format=mcpservers` flag
2. Ensure no MCP servers have malformed configurations
3. Check the raw output in the action logs for debugging

### Permission errors

If you encounter permission errors when saving the configuration file:
1. Ensure the output directory exists and is writable
2. Check GitHub Actions runner permissions
3. Consider using a path within the workspace directory

### Artifact upload fails

If artifact upload fails:
1. Ensure you're using a compatible version of `actions/upload-artifact`
2. Check that the configuration file was created successfully
3. Verify GitHub Actions artifact storage limits haven't been exceeded

## License

This action is part of the Stacklok Toolhive Actions collection and is licensed under the same terms as the parent repository.