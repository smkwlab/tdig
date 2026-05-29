# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tdig is a DNS lookup utility written in Elixir, similar to the Unix `dig` command. It supports dual build modes: escript for developers and Bakeware for standalone distribution.

## Core Architecture

The application follows a simple pipeline architecture:
- `Tdig.CLI` handles command-line argument parsing and option processing
- `Tdig` module contains the core DNS resolution logic
- Uses `tenbin_dns` library for DNS packet creation and parsing
- Supports both UDP and TCP transport protocols

Key modules:
- `Tdig.CLI` - CLI interface, argument parsing, and main entry point
- `Tdig` - Core DNS resolution, packet handling, and response formatting

## Development Commands

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run code quality checks
mix credo

# Run static analysis
mix dialyzer

# Build development release
mix compile

# Create escript version (for developers)
mix escript.build

# Create production release with Bakeware (for distribution)
MIX_ENV=prod mix release

# Run the application in development
mix run -- example.com A @8.8.8.8
```

## Testing

Tests are located in `test/tdig_test.exs` and focus on:
- CLI argument parsing functions
- String/atom conversion utilities
- Command-line option merging logic

Run tests with `mix test`.

## Dependencies

- `tenbin_dns` - DNS packet handling (custom fork)
- `socket` - Low-level socket operations
- `bakeware` - Creating standalone executables (Bakeware mode)
- `zoneinfo` - Timezone database for timestamp formatting

## Build Modes

### escript (Developer Mode)
- **Target audience**: Elixir developers, CI/CD environments
- **Requirements**: Erlang/Elixir runtime must be installed
- **Advantages**: Fast build, small file size, easy debugging
- **Build command**: `mix escript.build`
- **Output**: `./tdig` executable script

### Bakeware (Distribution Mode)  
- **Target audience**: End users, system administrators
- **Requirements**: No Erlang/Elixir runtime needed
- **Advantages**: Self-contained binary, no dependencies
- **Build command**: `MIX_ENV=prod mix release`
- **Output**: `./_build/prod/rel/bakeware/tdig` standalone binary

## Installation Options

### For Elixir Developers
```bash
# Install from source
git clone https://github.com/smkwlab/tdig.git
cd tdig
mix deps.get && mix escript.build
./tdig google.com A
```

### For End Users
Download the standalone binary from releases. Pre-built binaries are published per platform:

| Platform | Asset |
|---|---|
| Linux x86_64 | `tdig-linux-x86_64` |
| macOS arm64 (Apple Silicon) | `tdig-macos-arm64` |

```bash
# Auto-detect via uname
OS=$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/darwin/macos/')
ARCH=$(uname -m)
curl -L -o tdig "https://github.com/smkwlab/tdig/releases/latest/download/tdig-${OS}-${ARCH}"
chmod +x tdig
./tdig google.com A
```

## Release Process

Releases are produced by `.github/workflows/release.yml`, triggered automatically on tag push. There is **no scheduled/auto-bump trigger** — releasing is an explicit manual step performed by a maintainer.

### Tag convention
- Format: `X.Y.Z` (numeric semver, **no `v` prefix**, consistent with the pre-existing `0.2.0` tag)
- The workflow's tag filter is `'+([0-9]).+([0-9]).+([0-9])'` (extglob form for "digits.digits.digits"). Anything else (e.g., `v1.0.0`, `0.3.0-rc1`, `latest`) is silently ignored.

### Pre-release checklist
1. The change you want to release is merged to `main`.
2. `mix.exs` `:version` is bumped to the intended tag value (the workflow refuses to release if they diverge — this prevents `tdig --version` from lying about the published binary).
3. `mix test` / `mix credo --strict` / `mix format --check-formatted` all pass on `main`.

### Cutting a release

```bash
git checkout main
git pull
git tag 0.3.0           # must match mix.exs :version
git push origin 0.3.0   # ← this triggers the release workflow
```

### What the workflow does
1. **Build matrix** — runs in parallel on `ubuntu-latest` (Linux x86_64) and `macos-latest` (macOS arm64).
2. **Version guard** — fails fast if `Mix.Project.config()[:version]` ≠ pushed tag name.
3. **`MIX_ENV=prod mix release`** — produces the Bakeware binary at `_build/prod/rel/bakeware/tdig`.
4. **Rename + upload artifact** — saves as `tdig-linux-x86_64` / `tdig-macos-arm64`.
5. **Publish release** — collects both artifacts, then runs `gh release create <tag> --generate-notes <assets>`. Notes are auto-generated from PRs / commits since the previous tag.

### Bumping the version

```bash
# 1. Edit mix.exs: version: "0.4.0"
# 2. Commit (typically via PR) and merge to main
# 3. git tag 0.4.0 && git push origin 0.4.0
```

If you tag without first bumping `mix.exs`, the workflow's version guard aborts the release. Re-tag after fixing.

### Supported platforms

Initially Linux x86_64 + macOS arm64. To add a new target (e.g., Linux arm64, macOS x86_64), append an entry to the `matrix.include` list in `release.yml` with the appropriate runner and `asset_name`. Bakeware embeds the Erlang runtime so cross-compilation is not supported — each target needs a native runner.

## Configuration

- Elixir timezone database is configured to use Zoneinfo in `config/config.exs`
- Default DNS server is 8.8.8.8 when not specified
- Supports both IPv4 and IPv6 transport