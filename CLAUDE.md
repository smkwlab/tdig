# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tdig is a DNS lookup utility written in Elixir, similar to the Unix `dig` command. It's built as a CLI application using Bakeware for creating standalone executables.

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

# Create production release with Bakeware
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
- `bakeware` - Creating standalone executables
- `zoneinfo` - Timezone database for timestamp formatting

## Configuration

- Elixir timezone database is configured to use Zoneinfo in `config/config.exs`
- Default DNS server is 8.8.8.8 when not specified
- Supports both IPv4 and IPv6 transport