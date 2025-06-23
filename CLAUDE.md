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
2. It uses optimized tmux commands to detect existing Claude Code instances in the same git repository
   - **Performance Optimization**: Fast search prioritizes windows named "claude" in current session first
   - Falls back to comprehensive search across all sessions only if needed
   - Uses multiple detection methods including window name, command name, and Claude prompt verification
   - Automatically renames windows running Claude to "claude" for consistent identification
3. **Simple Instance Logic**: 
   - **0 instances** → Creates new one with appropriate flags
   - **1 instance** → Uses it automatically 
   - **2+ instances** → Shows picker (no remembering of choices)
4. If no instances exist, it creates a new tmux window running Claude Code
   - `<leader>cc` creates instances with `--continue` flag when auto-creating
   - `<leader>cn` always creates instances without any flags (clean Claude instances)
   - **Error Recovery**: Wraps Claude command with error handling to prevent pane closing
   - **Optimized Loading**: Uses early detection to reduce wait times (max 1.8s instead of 2.0s)
   - Shows animated loading indicator with early completion detection
   - Comprehensive error detection and user feedback for startup failures
5. The context is formatted as structured XML and sent to the Claude Code instance via tmux
   - Uses tmux buffers for reliable pasting
   - Includes retry logic for paste operations
6. If configured, focus automatically switches to the Claude Code pane
   - Uses a multi-step approach to ensure reliable window and pane selection
   - Includes verification and fallback mechanisms for window switching
7. When returning to Neovim, buffers are automatically reloaded to reflect any changes

## Recent Performance Improvements

- **Fast Instance Detection**: Prioritizes local session claude windows before doing expensive global search
- **Early Claude Ready Detection**: Stops waiting as soon as Claude prompt is detected
- **Simplified Verification**: Reduces redundant shell command execution
- **Better Error Handling**: Prevents pane closing issues with wrapped commands and clear error messages

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

## Configuration

The `claude_code_cmd` configuration option should only specify the command or path to Claude Code CLI, not include flags:

```lua
require("claude-tmux-neovim").setup({
  claude_code_cmd = "claude",  -- Just the command, no flags
  -- or with custom path:
  claude_code_cmd = "/path/to/claude",  -- Custom path, no flags
})
```

The plugin automatically adds appropriate flags:
- `<leader>cc` uses `--continue` flag when auto-creating instances
- `<leader>cn` uses no flags (clean instances)

## Development Guidelines

1. Follow existing code style and organization
2. Update documentation in both `README.md` and `doc/claude-tmux-neovim.txt` when making changes
3. Ensure backward compatibility with existing configurations
4. Verify compatibility with different tmux versions and configurations
5. Test with both normal and visual mode selection
6. Always include robust error handling and fallback mechanisms:
   - Verify panes and windows exist before attempting to use them
   - Include retry logic for operations that might fail initially
   - Provide informative debug logging for troubleshooting
   - Implement fallback approaches when primary methods fail
7. Test new features with both `<leader>cc` and `<leader>cn` commands
8. Ensure all tmux operations include proper error handling and debugging
9. When modifying tmux interaction code, test across different tmux sessions and window configurations
10. When adding visual elements (like loading indicators), ensure they work consistently across different terminal types
11. **IMPORTANT**: The `claude_code_cmd` config should only contain the command/path, never flags. Flags are added programmatically based on the operation.