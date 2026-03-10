# ToolHive GitHub Actions

[![Test](https://github.com/StacklokLabs/toolhive-actions/actions/workflows/test.yml/badge.svg)](https://github.com/StacklokLabs/toolhive-actions/actions/workflows/test.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

GitHub Actions for installing and running [ToolHive](https://github.com/stacklok/toolhive), a tool for managing Model Context Protocol (MCP) servers.

## 🚀 Quick Start

### Install ToolHive

```yaml
- name: Install ToolHive
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    version: latest  # or specify a version like 'v0.2.5'
```

### Run an MCP Server

```yaml
- name: Run Fetch MCP Server
  uses: stackloklabs/toolhive-actions/run-mcp-server@v0
  with:
    server: fetch
```

## 📦 Available Actions

### 1. `install` - Install ToolHive CLI

Installs the ToolHive CLI (`thv`) on your GitHub Actions runner.

**Features:**
- 🔍 Auto-detects OS and architecture
- 📌 Supports specific version installation
- ✅ Checksum verification for security
- 🚀 Caching for faster subsequent runs
- 🖥️ Cross-platform support (Linux, macOS, Windows)

[📖 Full Documentation](./install/README.md)

### 2. `run-mcp-server` - Run MCP Servers

Runs MCP servers using the installed ToolHive CLI.

**Features:**
- 📦 Run servers from ToolHive registry
- 🐳 Support for Docker images
- 🔧 Protocol schemes (uvx://, npx://, go://)
- 🔐 Secret management
- 📁 Volume mounting
- 🌐 Network isolation
- 🛠️ Tool filtering

[📖 Full Documentation](./run-mcp-server/README.md)

### 3. `mcp-config` - Save MCP Configuration

Persists MCP server configurations to a file and optionally uploads as an artifact.

**Features:**
- 💾 Save MCP server configurations
- 📤 Upload as GitHub Actions artifact
- 🏷️ Filter servers by labels
- 📊 JSON format output

[📖 Full Documentation](./mcp-config/README.md)

### 4. `skill-build` - Build ToolHive Skills

Build and optionally push a ToolHive skill as an OCI artifact.

**Features:**
- 🏗️ Build skills from a local directory containing `SKILL.md`
- 🏷️ Custom OCI tagging
- 📤 Push to any OCI-compatible registry (ghcr.io, Docker Hub, etc.)
- ✅ Validates skill structure before building

[📖 Full Documentation](./skill-build/README.md)

## 📚 Examples

### Basic Installation and Usage

```yaml
name: Use ToolHive
on: [push]

jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install ToolHive
        uses: StacklokLabs/toolhive-actions/install@v0
        
      - name: Run Fetch Server
        uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
        with:
          server: fetch
          
      - name: Use the MCP Server
        run: |
          # Your code that uses the MCP server
          echo "Server is running at ${{ steps.run-server.outputs.url }}"
```

### Advanced Usage with Secrets

```yaml
- name: Run GitHub MCP Server
  uses: stackloklabs/toolhive-actions/run-mcp-server@v0
  with:
    server: github
    secrets: |
      {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${{ secrets.GITHUB_TOKEN }}"
      }
```

### Using Docker Images

```yaml
- name: Run Custom MCP Server
  uses: StacklokLabs/toolhive-actions/run-mcp-server@v0
  with:
    server: my-org/my-mcp-server:latest
    transport: sse
    proxy-port: 8080
```

### Using Protocol Schemes

```yaml
- name: Run Python MCP Server
  uses: stackloklabs/toolhive-actions/run-mcp-server@v0
  with:
    server: uvx://my-python-mcp-server@latest
    volumes: |
      ./data:/app/data
```

## 🎯 Use Cases

- **AI-Powered CI/CD**: Integrate MCP servers into your workflows for AI-assisted tasks
- **Documentation Generation**: Use MCP servers to generate or update documentation
- **Code Analysis**: Run MCP servers for advanced code analysis and suggestions
- **Testing**: Use MCP servers in your test suites for AI-powered testing
- **Automation**: Automate complex tasks with MCP server capabilities

## 🔧 Requirements

- GitHub Actions runner (ubuntu-latest, macos-latest, or windows-latest)
- Docker or Podman (for running MCP servers on Linux)
- GitHub token (automatically provided in Actions)

## 📊 Compatibility Matrix

| Runner OS | Architecture | Install | Run Server | Notes |
|-----------|-------------|---------|------------|-------|
| Ubuntu    | amd64       | ✅      | ✅         | Fully supported |
| Ubuntu    | arm64       | ✅      | ✅         | Fully supported |
| macOS     | amd64       | ✅      | ⚠️         | See [#3](https://github.com/StacklokLabs/toolhive-actions/issues/3) |
| macOS     | arm64       | ✅      | ⚠️         | See [#3](https://github.com/StacklokLabs/toolhive-actions/issues/3) |
| Windows   | amd64       | ⚠️      | ✅         | See [#2](https://github.com/StacklokLabs/toolhive-actions/issues/2) |
| Windows   | arm64       | ⚠️      | ✅         | See [#2](https://github.com/StacklokLabs/toolhive-actions/issues/2) |

## ⚠️ Known Issues

### Windows: PowerShell PATH Issue ([#2](https://github.com/StacklokLabs/toolhive-actions/issues/2))
The `thv` command may not be recognized in PowerShell after installation. **Workarounds:**
- Use `shell: bash` in your workflow steps
- Reference the full path: `${{ steps.install.outputs.path }}`

### macOS: Container Runtime Not Available ([#3](https://github.com/StacklokLabs/toolhive-actions/issues/3))
ToolHive cannot run MCP servers on macOS runners due to missing container runtime. **Workarounds:**
- Use Linux runners for running MCP servers
- Use macOS only for installation testing

For the latest status and updates on these issues, please check the [issues page](https://github.com/StacklokLabs/toolhive-actions/issues).

## 🔒 Security

- All downloads are verified using checksums
- Runs with minimal required permissions
- Secrets are handled securely
- Network isolation available for enhanced security

## 📝 Versioning

We use semantic versioning and maintain major version tags:

- `@v0` - Latest v0.x.x release (recommended for stability)
- `@v0.0.2` - Specific version
- `@main` - Latest development version (not recommended for production)

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

### Development Setup

```bash
# Clone the repository
git clone https://github.com/StacklokLabs/toolhive-actions.git
cd toolhive-actions

# Test the actions locally using act (https://github.com/nektos/act)
act -W .github/workflows/test.yml

# Or push to a branch and let GitHub Actions run the tests
git checkout -b test-branch
git push origin test-branch
```

### Testing in Your Own Workflow

To test these actions in your own repository:

```yaml
name: Test ToolHive Actions
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install ToolHive
        uses: StacklokLabs/toolhive-actions/install@v0
        
      - name: Verify installation
        run: thv version
```

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## 🔗 Related Projects

- [ToolHive](https://github.com/stacklok/toolhive) - The main ToolHive project
- [ToolHive Documentation](https://docs.stacklok.com/toolhive) - Official documentation
- [MCP Specification](https://modelcontextprotocol.io) - Model Context Protocol specification

## 💬 Support

- [GitHub Issues](https://github.com/StacklokLabs/toolhive-actions/issues) - Bug reports and feature requests
- [Discord](https://discord.gg/stacklok) - Community support and discussions
- [Documentation](https://docs.stacklok.com/toolhive) - Official ToolHive documentation

