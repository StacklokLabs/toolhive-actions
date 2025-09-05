# Run MCP Server Action

This action runs Model Context Protocol (MCP) servers using ToolHive, enabling AI-powered capabilities in your GitHub Actions workflows.

## Features

- 📦 **Multiple server sources**: Run from ToolHive registry, Docker images, or protocol schemes
- 🔧 **Flexible configuration**: Support for different transport methods and configurations
- 📁 **Volume mounting**: Mount local directories into server containers
- 🌐 **Network control**: Optional network isolation for enhanced security
- 🛠️ **Tool filtering**: Expose only specific tools from the server
- ⏱️ **Health checks**: Wait for server readiness before continuing

## Prerequisites

- ToolHive CLI must be installed (use the `install` action first)
- Docker or Podman must be available on the runner

## Usage

### Basic Usage

```yaml
- name: Install ToolHive
  uses: StacklokLabs/toolhive-actions/install@v0

- name: Run Fetch MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: fetch
```

### Run from Docker Image

```yaml
- name: Run Custom MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: ghcr.io/my-org/my-mcp-server:latest
    transport: sse
    proxy-port: 8080
```

### Run with Protocol Schemes

```yaml
# Python package via uvx
- name: Run Python MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: uvx://my-python-mcp@latest

# Node.js package via npx
- name: Run Node.js MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: npx://my-node-mcp@latest

# Go package
- name: Run Go MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: go://github.com/user/mcp-server@latest
```

### Advanced Configuration

```yaml
- name: Run MCP Server with Full Configuration
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: my-mcp-server
    name: custom-instance
    transport: streamable-http
    proxy-port: 9000
    target-port: 8080
    volumes: |
      ./data:/app/data
      ./config:/app/config
    network-isolation: true
    tools: fetch,analyze,generate
    arguments: --verbose --config /app/config/settings.json
    wait-for-ready: true
    timeout: 60
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `server` | MCP server to run (registry name, Docker image, or protocol scheme) | Yes | - |
| `name` | Custom name for the server instance | No | - |
| `transport` | Transport method (`stdio`, `sse`, `streamable-http`) | No | `stdio` |
| `proxy-port` | Port for the proxy server | No | Random |
| `target-port` | Target port for SSE/streamable-http transport | No | - |
| `volumes` | Volume mounts (one per line, format: `host_path:container_path`) | No | - |
| `network-isolation` | Enable network isolation | No | `false` |
| `tools` | Comma-separated list of tools to expose | No | All tools |
| `arguments` | Additional arguments to pass to the server | No | - |
| `ca-cert` | Path to CA certificate for TLS | No | - |
| `permission-profile` | Path to custom permission profile JSON | No | - |
| `wait-for-ready` | Wait for server to be ready before continuing | No | `true` |
| `timeout` | Timeout in seconds for server to be ready | No | `30` |

## Outputs

| Output | Description |
|--------|-------------|
| `url` | The URL of the running MCP server |
| `port` | The port of the running MCP server |
| `status` | The status of the MCP server |
| `container-name` | The name of the container running the server |

## Examples

### Using Server Output in Subsequent Steps

```yaml
- name: Run MCP Server
  id: mcp
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: fetch

- name: Use Server Information
  run: |
    echo "Server URL: ${{ steps.mcp.outputs.url }}"
    echo "Server Port: ${{ steps.mcp.outputs.port }}"
    echo "Server Status: ${{ steps.mcp.outputs.status }}"
    
    # Make a request to the server
    curl "${{ steps.mcp.outputs.url }}/health"
```

### Running Multiple Servers

```yaml
- name: Run GitHub MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: github
    name: github-server

- name: Run Fetch MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: fetch
    name: fetch-server

- name: List Running Servers
  run: thv list
```

### With Volume Mounts

```yaml
- name: Checkout Code
  uses: actions/checkout@v4

- name: Run Analysis Server with Code Access
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: code-analyzer
    volumes: |
      ${{ github.workspace }}:/workspace:ro
    arguments: --analyze /workspace
```

### With Network Isolation

```yaml
- name: Run Isolated MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: sensitive-processor
    network-isolation: true
    permission-profile: ./security/mcp-permissions.json
```

### Tool Filtering

```yaml
- name: Run Server with Limited Tools
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: multi-tool-server
    tools: safe_read,safe_write
    # Only expose safe_read and safe_write tools, hiding others
```

## Transport Methods

### stdio (Default)
Standard input/output communication. Most compatible and secure.

```yaml
transport: stdio
```

### SSE (Server-Sent Events)
HTTP-based communication with server-sent events.

```yaml
transport: sse
target-port: 8080  # Optional: specify container port
```

### Streamable HTTP
Modern HTTP-based protocol (MCP spec 2025-03-26+).

```yaml
transport: streamable-http
target-port: 8080  # Optional: specify container port
```

## Security Considerations

### Network Isolation
Enable network isolation to restrict server network access:

```yaml
network-isolation: true
```

### Permission Profiles
Use custom permission profiles for fine-grained control:

```yaml
permission-profile: ./permissions.json
```

Example permission profile:
```json
{
  "network": {
    "allowed_hosts": ["api.github.com", "api.openai.com"],
    "block_local": true
  },
  "filesystem": {
    "read_paths": ["/workspace"],
    "write_paths": ["/tmp"]
  }
}
```

### Volume Mounting Best Practices
- Use read-only mounts when possible (`:ro` suffix)
- Mount only necessary directories
- Avoid mounting sensitive directories

## TODO: Secrets Management

Secrets support is planned for a future release. The implementation will include:

- Integration with ToolHive's encrypted secrets storage
- Support for 1Password integration
- Mapping GitHub secrets to ToolHive secrets
- Secure passing of API keys and tokens to MCP servers

For now, you can set environment variables directly in your workflow if needed.

## Troubleshooting

### Server Fails to Start

1. Check Docker/Podman is available:
```yaml
- name: Check Docker
  run: docker version
```

2. Verify ToolHive is installed:
```yaml
- name: Check ToolHive
  run: thv version
```

3. Check server logs:
```yaml
- name: View Logs
  if: failure()
  run: thv logs ${{ inputs.server }}
```

### Server Not Ready

Increase the timeout:
```yaml
timeout: 120  # 2 minutes
```

Or disable waiting:
```yaml
wait-for-ready: false
```

### Port Conflicts

Specify a different proxy port:
```yaml
proxy-port: 9999
```

### Container Runtime Issues

The action automatically detects Docker or Podman. If you have both, Docker is preferred. To force Podman:

```yaml
- name: Set Container Runtime
  run: echo "CONTAINER_RUNTIME=podman" >> $GITHUB_ENV

- name: Run MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: fetch
```

## Server Cleanup

Servers are automatically cleaned up when the job completes. To manually stop a server:

```yaml
- name: Stop Server
  run: thv stop my-server-name
```

To stop all servers:

```yaml
- name: Stop All Servers
  run: thv stop --all
```

## Performance Tips

1. **Pre-pull Images**: For faster startup, pre-pull Docker images in a previous step
2. **Reuse Servers**: Keep servers running across multiple steps when possible
3. **Parallel Execution**: Run independent servers in parallel jobs

## Contributing

Contributions are welcome! Please see the main [Contributing Guide](../CONTRIBUTING.md) for details.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/StacklokLabs/toolhive-actions/issues)
- [Discord Community](https://discord.gg/stacklok)
- [ToolHive Documentation](https://docs.stacklok.com/toolhive)

## Related Documentation

- [ToolHive CLI Reference](https://docs.stacklok.com/toolhive/reference/cli/thv)
- [MCP Specification](https://modelcontextprotocol.io)
- [ToolHive Registry](https://docs.stacklok.com/toolhive/guides-cli/registry)