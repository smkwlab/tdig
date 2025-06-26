# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tdig is a DNS lookup utility written in Elixir, similar to the Unix `dig` command. It's built as a CLI application using Burrito for creating standalone executables.

## Burrito Migration Notes

**Current Status**: Successfully migrated to Burrito
**Previous Tool**: Bakeware (removed)

**Migration Completed**:
- ✅ Removed bakeware dependencies
- ✅ Added burrito dependency (v1.3.0)
- ✅ Updated mix.exs configuration
- ✅ Created Tdig.Application module for OTP entry point
- ✅ Configured custom ERTS: otp_27.3.4.1_darwin_aarch64_custom.tar.gz

**Benefits Achieved**:
- Smaller binary sizes
- Better cross-platform support  
- Active maintenance and updates

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

# Create production release with Burrito
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
- `burrito` - Creating standalone executables  
- `zoneinfo` - Timezone database for timestamp formatting

## Configuration

- Elixir timezone database is configured to use Zoneinfo in `config/config.exs`
- Default DNS server is 8.8.8.8 when not specified
- Supports both IPv4 and IPv6 transport