# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude-tmux-neovim is a Neovim plugin that seamlessly integrates with Claude Code via tmux. It allows you to send rich code context (file path, git root, line numbers, selection, full content) to Claude Code instances running in tmux panes with a single keystroke.

## Architecture

The plugin uses a modular architecture:

- `init.lua` - Main entry point with public API
- `lib/config.lua` - Configuration management and state tracking
- `lib/util.lua` - Utility functions for file and text operations
- `lib/tmux.lua` - Tmux interaction and Claude Code instance management
- `lib/context.lua` - Context generation and XML formatting
- `lib/debug.lua` - Debug logging functionality
- `lib/silent.lua` - Handles silent operations for better UX

## Core Workflow

1. When triggered, the plugin captures code context (file path, git root, cursor position, and optionally selected code)
2. It uses tmux commands to detect existing Claude Code instances in the same git repository
3. If no instances exist, it creates a new tmux window running Claude Code
4. The context is formatted as structured XML and sent to the Claude Code instance via tmux
5. If configured, focus automatically switches to the Claude Code pane
6. When returning to Neovim, buffers are automatically reloaded to reflect any changes

## Development Commands

### Building and Testing

The plugin is written in Lua and doesn't require a build step. To test changes:

1. Make changes to the code
2. Source the changed files or restart Neovim
3. Use the plugin functionality to verify changes

### Debug Mode

For troubleshooting during development:

1. Enable debug mode in your configuration or use `:ClaudeCodeDebug`
2. View the debug log with `:ClaudeCodeShowLog`
3. Clear the debug log with `:ClaudeCodeClearLog`

The debug log is stored at: `vim.fn.stdpath('cache') .. '/claude-tmux-neovim-debug.log'`

### Key Files for Development

- `lua/claude-tmux-neovim/init.lua`: Main entry point and API
- `lua/claude-tmux-neovim/lib/tmux.lua`: Core functionality for tmux integration
- `lua/claude-tmux-neovim/lib/context.lua`: Context creation and formatting

## Development Guidelines

1. Follow existing code style and organization
2. Update documentation in both `README.md` and `doc/claude-tmux-neovim.txt` when making changes
3. Ensure backward compatibility with existing configurations
4. Verify compatibility with different tmux versions and configurations
5. Test with both normal and visual mode selection