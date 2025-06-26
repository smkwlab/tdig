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
Download the standalone binary from releases:
```bash
curl -L -o tdig https://github.com/smkwlab/tdig/releases/latest/download/tdig
chmod +x tdig
./tdig google.com A
```

## Configuration

- Elixir timezone database is configured to use Zoneinfo in `config/config.exs`
- Default DNS server is 8.8.8.8 when not specified
- Supports both IPv4 and IPv6 transport