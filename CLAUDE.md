# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude-tmux-neovim is a Neovim plugin that seamlessly integrates with Claude Code via tmux. It allows you to send rich code context (file path, git root, line numbers, selection, full content) to Claude Code instances running in tmux panes with a single keystroke.

Repository: https://github.com/karlhepler/claude-tmux-neovim
License: MIT

## Development Commands

### Testing Changes

Since this is a pure Lua plugin with no formal test suite, testing is manual:

1. Make changes to Lua files
2. Either restart Neovim or use `:source %` on changed files  
3. Test functionality manually using the plugin commands
4. Use built-in debug mode for troubleshooting:
   - Enable: `:ClaudeCodeDebug` or set `debug = true` in config
   - View logs: `:ClaudeCodeShowLog`
   - Clear logs: `:ClaudeCodeClearLog`
   - Log location: `vim.fn.stdpath('cache') .. '/claude-tmux-neovim-debug.log'`

### Available Commands

- `:ClaudeCodeSend` - Send current file context to Claude Code
- `:ClaudeCodeNew` - Create new Claude instance and send context
- `:ClaudeCodeReload` - Manually reload all Neovim buffers
- `:ClaudeCodeDebug` - Toggle debug mode
- `:ClaudeCodeShowLog` - Show debug log in split window
- `:ClaudeCodeClearLog` - Clear debug log file
- `:ClaudeCodeReset` - Clear remembered instance choice (NOT IMPLEMENTED - see config.lua)

### Common Development Tasks

**Adding a new config option:**
1. Add to `lib/config.lua` with validation in the defaults table
2. Update README.md and doc/claude-tmux-neovim.txt documentation
3. Test with both valid and invalid values

**Adding tmux operations:**
1. Use `lib/tmux_commands.lua` utilities for consistent error handling
2. Include retry logic for operations that might fail initially
3. Add debug logging for troubleshooting

**Handling visual selections:**
1. Use `lib/selection_utils.lua` functions
2. Don't duplicate selection logic - it's already consolidated

**Adding error cases:**
1. Use appropriate methods from `lib/error_handler.lua`
2. Follow existing patterns: `tmux_error`, `git_error`, `file_error`, etc.
3. Use `safe_execute` wrapper for critical operations

**Creating new user commands:**
1. Add to `create_user_commands()` function in `init.lua`
2. Follow the pattern of existing commands with proper error handling
3. Update documentation in both README.md and doc/claude-tmux-neovim.txt

## Architecture

The plugin uses a modular architecture with recent refactoring for improved maintainability:

### Core Modules
- `init.lua` - Main entry point with public API and user commands
- `lib/config.lua` - Configuration management with validation
- `lib/util.lua` - Utility functions for file and text operations

### Tmux Integration Layer
- `lib/tmux.lua` - Legacy tmux interaction (being gradually refactored)
- `lib/tmux_commands.lua` - Centralized tmux command execution utilities
- `lib/instance_detection.lua` - Modular Claude instance detection and verification

### Context and Communication
- `lib/context.lua` - Context generation and XML formatting
- `lib/selection_utils.lua` - Unified visual selection handling
- `lib/silent.lua` - Silent operation handlers for keymaps

### Infrastructure
- `lib/constants.lua` - Centralized constants, timeouts, and configuration values
- `lib/error_handler.lua` - Consistent error handling and validation
- `lib/debug.lua` - Debug logging functionality

## Core Workflow

1. When triggered, the plugin captures code context (file path, git root, cursor position, and optionally selected code)
2. It uses guaranteed process detection to find Claude instances:
   - **Primary Method**: `ps aux | awk '$11 == "claude"'` finds all Claude processes
   - Maps Claude PIDs to tmux panes via parent PIDs
   - Filters by git repository working directory
3. **Simple Instance Logic**: 
   - **0 instances** → Creates new one with appropriate flags
   - **1 instance** → Uses it automatically 
   - **2+ instances** → Shows picker (no remembering of choices currently)
4. If no instances exist, it creates a new tmux window running Claude Code
   - `<leader>cc` creates instances with `--continue` flag when auto-creating
   - `<leader>cn` always creates instances without any flags (clean Claude instances)
   - **Error Recovery**: Wraps Claude command with error handling to prevent pane closing
   - Shows animated loading indicator with early completion detection
5. The context is formatted as structured XML and sent to the Claude Code instance via tmux
   - Uses tmux buffers for reliable pasting
   - Includes retry logic for paste operations
   - Verifies Claude is ready (not in menus) before pasting
6. If configured, focus automatically switches to the Claude Code pane
7. When returning to Neovim, buffers are automatically reloaded to reflect any changes

## Configuration

The `claude_code_cmd` configuration option should only specify the command or path to Claude Code CLI, not include flags:

```lua
require("claude-tmux-neovim").setup({
  claude_code_cmd = "claude",  -- Just the command, no flags
  -- or with custom path:
  claude_code_cmd = "/path/to/claude",  -- Custom path, no flags
})
```

The plugin automatically adds appropriate flags based on the operation.

## Development Guidelines

1. **No formal build/test/lint process** - The codebase relies on manual testing
2. **Use centralized modules** - Prefer `error_handler.lua`, `constants.lua`, etc. over duplicating code
3. **Add constants properly** - Use `constants.lua` instead of magic numbers/strings
4. **Test error conditions** - Include robust error handling with the centralized error handler
5. **Follow module patterns** - Each module should have clear responsibilities and minimal coupling
6. **Update documentation** - Keep README.md and doc/claude-tmux-neovim.txt in sync
7. **Test both commands** - Verify with both `<leader>cc` and `<leader>cn`
8. **Preserve backward compatibility** - Don't break existing configurations
9. **Add debug logging** - Use `lib/debug.lua` for new functionality
10. **Handle edge cases** - Test with multiple tmux sessions, missing git repos, etc.
11. **Document functions** - Use LuaLS annotations (`---@param`, `---@return`) for documentation

## Code Patterns

### Module Structure
```lua
local M = {}
local dependency = require('module.dependency')

--- Function description
---@param param type Description
---@return type description
function M.function_name(param)
  -- implementation
end

return M
```

### Constants Usage
Always define constants in `lib/constants.lua`:
```lua
M.MY_CONSTANT = {
  VALUE = "value",
  TIMEOUT = 1000,
}
```

### Error Handling
Use the centralized error handler:
```lua
local error_handler = require('claude-tmux-neovim.lib.error_handler')

-- For specific error types
error_handler.tmux_error("Failed to create pane")

-- For safe execution
local success = error_handler.safe_execute(function()
  -- risky operation
end, "operation_type", "Error message", notify_user)
```

## Testing Checklist

When making changes, manually test:

1. **Basic Operations**
   - [ ] `<leader>cc` with no Claude instances (should create one)
   - [ ] `<leader>cc` with one Claude instance (should use it)
   - [ ] `<leader>cc` with multiple Claude instances (should show picker)
   - [ ] `<leader>cn` (should always create new instance)

2. **Visual Mode**
   - [ ] Select code and use `<leader>cc`
   - [ ] Select code and use `<leader>cn`

3. **Edge Cases**
   - [ ] Non-git directory behavior
   - [ ] Claude instance in different git repository
   - [ ] Claude instance showing menu/not ready
   - [ ] Multiple tmux sessions
   - [ ] Claude instance that crashes/exits

4. **Configuration**
   - [ ] Custom keymaps work
   - [ ] `auto_switch_pane = false` works
   - [ ] `auto_reload_buffers = false` works
   - [ ] Debug mode logs correctly

## Known Issues

- `:ClaudeCodeReset` command is defined but not implemented (no state persistence)
- Unicode box-drawing characters may have detection issues in some terminal encodings
- Window name-based detection is unreliable and used only as last resort

## Key Architectural Decisions

- **Process-first detection**: Uses `ps aux` to find Claude processes by name
- **No persistent state**: Plugin doesn't save state between sessions (except debug logs)
- **Git-centric**: All operations assume git repository context
- **Tmux-dependent**: Core functionality requires tmux environment
- **XML communication**: Uses structured XML format for Claude context
- **Multiple verification layers**: Ensures reliability through redundant checks
- **User-first error handling**: Clear error messages with actionable information