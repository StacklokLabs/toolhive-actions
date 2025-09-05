# Install ToolHive Action

This action installs the ToolHive CLI (`thv`) on GitHub Actions runners, enabling you to manage MCP (Model Context Protocol) servers in your workflows.

## Features

- 🔍 **Auto-detection**: Automatically detects the runner's OS and architecture
- 📌 **Version control**: Install specific versions or always get the latest
- ✅ **Security**: Optional checksum verification for downloaded binaries
- 🚀 **Performance**: Caches installations for faster subsequent runs
- 🖥️ **Cross-platform**: Works on Linux, macOS, and Windows runners

## Usage

### Basic Usage

```yaml
- name: Install ToolHive
  uses: StacklokLabs/toolhive-actions/install@v0
```

### Install Specific Version

```yaml
- name: Install ToolHive v0.2.5
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    version: v0.2.5
```

### Custom Installation Directory

```yaml
- name: Install ToolHive to custom directory
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    install-dir: /opt/toolhive
```

### Disable Checksum Verification

```yaml
- name: Install ToolHive without checksum verification
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    verify-checksum: false
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `version` | ToolHive version to install (e.g., "v0.2.5" or "latest") | No | `latest` |
| `verify-checksum` | Verify the checksum of the downloaded binary | No | `true` |
| `github-token` | GitHub token for API requests | No | `${{ github.token }}` |
| `install-dir` | Directory to install ToolHive | No | `~/.toolhive/bin` |

## Outputs

| Output | Description |
|--------|-------------|
| `version` | The installed ToolHive version |
| `path` | The path to the installed ToolHive binary |

## Examples

### Complete Workflow Example

```yaml
name: Use ToolHive
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  example:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install ToolHive
        id: install-toolhive
        uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: latest
      
      - name: Display installed version
        run: |
          echo "Installed version: ${{ steps.install-toolhive.outputs.version }}"
          echo "Binary path: ${{ steps.install-toolhive.outputs.path }}"
          thv version
      
      - name: List available MCP servers
        run: thv registry list
```

### Matrix Testing Example

```yaml
name: Test on Multiple Platforms
on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
        version: [latest, v0.2.5, v0.2.4]
    
    runs-on: ${{ matrix.os }}
    steps:
      - name: Install ToolHive
        uses: StacklokLabs/toolhive-actions/install@v0
        with:
          version: ${{ matrix.version }}
      
      - name: Verify installation
        run: thv version
```

### Caching Example

The action automatically caches installations. Here's how it works:

```yaml
- name: Install ToolHive (first run - downloads)
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    version: v0.2.5

# In subsequent runs with the same version/OS/arch,
# the cached version will be used automatically
- name: Install ToolHive (subsequent runs - uses cache)
  uses: StacklokLabs/toolhive-actions/install@v0
  with:
    version: v0.2.5
```

## Platform Support

| Platform | Architecture | Status |
|----------|-------------|--------|
| Linux | amd64 | ✅ Supported |
| Linux | arm64 | ✅ Supported |
| macOS | amd64 | ✅ Supported |
| macOS | arm64 | ✅ Supported |
| Windows | amd64 | ✅ Supported |
| Windows | arm64 | ✅ Supported |

## Troubleshooting

### Rate Limiting

If you encounter GitHub API rate limiting issues, ensure you're using the `github-token` input:

```yaml
- uses: StacklokLabs/toolhive-actions/install@v0
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Checksum Verification Failures

If checksum verification fails, you can:

1. Retry the workflow (might be a download issue)
2. Temporarily disable verification (not recommended for production):

```yaml
- uses: StacklokLabs/toolhive-actions/install@v0
  with:
    verify-checksum: false
```

### Permission Issues

On Linux runners, if you encounter permission issues:

```yaml
- name: Install ToolHive
  uses: StacklokLabs/toolhive-actions/install@v0
  
- name: Fix permissions
  run: chmod +x ~/.toolhive/bin/thv
```

### Windows Path Issues

On Windows runners, if `thv` is not found after installation:

```yaml
- name: Install ToolHive
  uses: StacklokLabs/toolhive-actions/install@v0
  
- name: Verify installation
  shell: pwsh
  run: |
    $env:PATH = "$env:USERPROFILE\.toolhive\bin;$env:PATH"
    thv version
```

## Security Considerations

1. **Checksum Verification**: Always enabled by default to ensure binary integrity
2. **HTTPS Downloads**: All downloads use HTTPS from official GitHub releases
3. **Token Usage**: Uses GitHub token to avoid rate limiting and access private repos if needed
4. **Minimal Permissions**: Runs with minimal required permissions

## Performance Tips

1. **Use Caching**: The action automatically caches installations
2. **Specify Versions**: Using specific versions instead of `latest` avoids API calls
3. **Parallel Jobs**: When using matrix builds, installations can run in parallel

## Contributing

Contributions are welcome! Please see the main [Contributing Guide](../CONTRIBUTING.md) for details.

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](../LICENSE) file for details.

## Support

- [GitHub Issues](https://github.com/StacklokLabs/toolhive-actions/issues)
- [Discord Community](https://discord.gg/stacklok)
- [ToolHive Documentation](https://docs.stacklok.com/toolhive)