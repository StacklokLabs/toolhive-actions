# ToolHive GitHub Actions - Comprehensive Plan

## Overview
This project provides GitHub Actions for installing and running ToolHive, a tool for managing Model Context Protocol (MCP) servers. The actions enable CI/CD workflows to easily integrate MCP servers for AI-powered development tasks.

## Architecture Decision: Single Repository
We will use a **single repository** (`toolhive-actions`) containing multiple actions for the following reasons:
- Both actions are closely related to ToolHive functionality
- Easier maintenance and synchronized versioning
- Shared utilities and common code
- Users can reference all actions from one repository
- Simplified documentation and examples

## Actions to Implement

### 1. Install ToolHive Action (`install`)
**Purpose**: Download and install the ToolHive CLI (`thv`) on GitHub Actions runners.

**Key Features**:
- Auto-detect runner OS (Linux, macOS, Windows) and architecture (amd64, arm64)
- Support version specification (default: latest)
- Download from official GitHub releases
- Verify checksums for security
- Add binary to PATH
- Cache installation for faster subsequent runs

**Inputs**:
- `version`: ToolHive version to install (default: 'latest')
- `verify-checksum`: Whether to verify download checksum (default: true)
- `github-token`: GitHub token for API requests (default: ${{ github.token }})

**Outputs**:
- `version`: Installed ToolHive version
- `path`: Path to installed binary

### 2. Run MCP Server Action (`run-mcp-server`)
**Purpose**: Run MCP servers using the installed ToolHive CLI.

**Key Features**:
- Support multiple server sources:
  - ToolHive registry (by name)
  - Docker images
  - Protocol schemes (uvx://, npx://, go://)
- Configure transport methods (stdio, sse, streamable-http)
- Pass secrets and environment variables
- Mount volumes for file access
- Network isolation options
- Tool filtering capabilities

**Inputs**:
- `server`: Server to run (name/image/scheme)
- `transport`: Transport method (default: 'stdio')
- `proxy-port`: Port for proxy (optional)
- `secrets`: JSON object of secrets to pass
- `volumes`: Volume mounts (multiline string)
- `network-isolation`: Enable network isolation (default: false)
- `tools`: Comma-separated list of tools to expose
- `arguments`: Additional arguments for the server
- `name`: Custom name for the server instance

**Outputs**:
- `url`: Server URL
- `port`: Server port
- `status`: Server status

## Project Structure
```
toolhive-actions/
├── .github/
│   └── workflows/
│       ├── test.yml          # Test workflow for the actions
│       ├── release.yml       # Release automation
│       └── ci.yml            # Continuous integration
├── install/
│   ├── action.yml            # Install action definition
│   ├── README.md             # Install action documentation
│   └── scripts/
│       ├── install.sh        # Unix installation script
│       └── install.ps1       # Windows installation script
├── run-mcp-server/
│   ├── action.yml            # Run action definition
│   ├── README.md             # Run action documentation
│   └── scripts/
│       ├── run.sh            # Unix run script
│       └── run.ps1           # Windows run script
├── examples/
│   ├── basic-install.yml     # Basic installation example
│   ├── run-fetch-server.yml  # Run fetch server example
│   ├── run-with-secrets.yml  # Using secrets example
│   ├── run-with-volumes.yml  # Volume mounting example
│   └── advanced-usage.yml    # Advanced features example
├── tests/
│   ├── install/              # Install action tests
│   └── run-mcp-server/       # Run action tests
├── README.md                 # Main documentation
├── LICENSE                   # MIT License
└── CONTRIBUTING.md           # Contribution guidelines
```

## Implementation Details

### OS/Architecture Detection
```bash
# Linux/macOS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
# Convert arch names
case $ARCH in
  x86_64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
esac
```

### Download URL Pattern
```
https://github.com/stacklok/toolhive/releases/download/${VERSION}/toolhive_${VERSION#v}_${OS}_${ARCH}.tar.gz
# Windows uses .zip instead of .tar.gz
```

### Caching Strategy
- Use GitHub Actions cache with key: `toolhive-${version}-${os}-${arch}`
- Cache location: `~/.toolhive/bin`

### Error Handling
- Validate all inputs
- Check for required dependencies (Docker/Podman for run action)
- Provide clear error messages
- Set exit codes appropriately

## Testing Strategy

### Unit Tests
- OS/architecture detection logic
- URL construction
- Input validation

### Integration Tests (GitHub Actions)
- Test matrix across:
  - OS: [ubuntu-latest, macos-latest, windows-latest]
  - Architecture: [amd64, arm64] (where available)
  - ToolHive versions: [latest, specific versions]

### Example Workflows
- Demonstrate real-world usage patterns
- Cover all major features
- Include troubleshooting guides

## Documentation

### Main README
- Quick start guide
- Feature overview
- Links to individual action docs
- Contributing guidelines

### Action-specific READMEs
- Detailed input/output descriptions
- Usage examples
- Troubleshooting
- Version compatibility

### Examples
- Well-commented workflow files
- Progressive complexity (basic → advanced)
- Real-world use cases

## Versioning Strategy
- Use semantic versioning (v1.0.0)
- Maintain major version tags (v1, v2)
- Document breaking changes
- Provide migration guides

## Security Considerations
- Always verify checksums when downloading
- Use GitHub token for API requests to avoid rate limits
- Sanitize all inputs
- Run in least-privilege mode
- Document security best practices

## Future Enhancements
- Support for ToolHive configuration files
- Integration with GitHub Environments
- Metrics and telemetry options
- Support for multiple server instances
- Server health checks and monitoring

## Success Criteria
- [ ] Actions work on all major OS/arch combinations
- [ ] Clear, comprehensive documentation
- [ ] Robust error handling
- [ ] Fast execution (with caching)
- [ ] Security best practices followed
- [ ] Easy to use for beginners
- [ ] Flexible for advanced users
- [ ] Well-tested and reliable

## Timeline
1. Week 1: Create folder structure and basic action definitions
2. Week 2: Implement install action with tests
3. Week 3: Implement run-mcp-server action with tests
4. Week 4: Documentation, examples, and polish
5. Week 5: Community feedback and iteration

## Maintenance Plan
- Regular updates for new ToolHive releases
- Monitor and respond to issues
- Keep dependencies updated
- Maintain compatibility with GitHub Actions changes
- Regular security audits