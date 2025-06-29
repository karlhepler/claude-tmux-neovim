# claude-tmux-neovim

A Neovim plugin that seamlessly integrates with Claude Code via tmux, allowing you to send rich code context to Claude Code instances with a single keystroke.

## Overview

Imagine you're coding in Neovim and need Claude's help. Instead of copying code, switching windows, and pasting into Claude, you simply:

1. **Press `<leader>cc`** - The plugin instantly captures your current file, cursor position, and any selected code
2. **Claude appears** - Either in an existing Claude Code window or a new one (with `--continue` flag for context continuity)
3. **Context is sent** - Your code appears in Claude formatted as XML with full file context, ready for discussion
4. **Focus switches** - You're automatically placed in the Claude pane to start your conversation
5. **Changes sync back** - When you return to Neovim, any files Claude modified are automatically reloaded

For a fresh Claude session without history, use `<leader>cn` instead. The plugin intelligently manages Claude instances per git repository, and when multiple instances exist, it can remember your choice to avoid showing the picker repeatedly.

## Why use this plugin?

- **Zero friction AI assistance**: Get help without breaking your flow - it's as fast as running a vim command
- **Full context awareness**: Claude sees not just your selection, but the entire file, git root, and cursor location
- **Smart instance management**: Works with your existing Claude sessions or creates new ones intelligently
- **Git-aware isolation**: Only shows Claude instances from your current repository, keeping projects separate
- **Automatic synchronization**: Changes made by Claude are instantly reflected when you return to Neovim

This plugin transforms Claude Code from a separate tool into an extension of your editor, making AI-assisted coding feel native to your Neovim workflow.

## Features

- Press `<leader>cc` to send context to Claude Code (uses `claude --continue` when auto-creating instances)
- Press `<leader>cn` to create a new Claude Code instance and send context (always uses plain `claude` without flags)
- Works with visual selections for more targeted assistance in both normal and visual modes
- Git repository isolation - only shows Claude Code instances in the same git repository
- Smart instance management:
  - Detects existing Claude Code instances in the correct git root with strict verification
  - Shows detection method in selection menu ([cmd], [node], [prompt], [renamed], etc.)
  - Automatically renames tmux windows to "claude" for consistency
  - Creates new instances if none exist with robust pane tracking
  - Remembers your instance choice when multiple exist (skip picker on subsequent uses)
  - Automatic retry mechanisms for tmux operations
- Automatically switches to Claude Code pane after sending context with fallback mechanisms
- Automatically reloads Neovim buffers when focus returns from Claude Code
- Sends rich context in XML format optimized for LLMs
- Comprehensive debug mode for troubleshooting with detailed logging
- Animated loading indicator during Claude Code instance startup

## Requirements

- Neovim 0.7.0 or newer
- tmux
- Claude Code CLI
- Git

## Installation

### Using a Plugin Manager (Recommended)

#### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "karlhepler/claude-tmux-neovim",
  config = function()
    require("claude-tmux-neovim").setup({
      -- your configuration
    })
  end,
}
```

#### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "karlhepler/claude-tmux-neovim",
  config = function()
    require("claude-tmux-neovim").setup()
  end
}
```

#### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'karlhepler/claude-tmux-neovim'
```

Then in your Lua config:

```lua
require("claude-tmux-neovim").setup()
```

### Manual Installation

Clone the repository:

```bash
git clone https://github.com/karlhepler/claude-tmux-neovim.git \
  ~/.local/share/nvim/site/pack/plugins/start/claude-tmux-neovim
```


## Configuration

Add this to your Neovim config:

```lua
require("claude-tmux-neovim").setup({
  keymap = "<leader>cc",           -- Key binding for sending context
  keymap_new = "<leader>cn",       -- Key binding for creating new Claude instance
  claude_code_cmd = "claude",      -- Command/path to Claude Code CLI (no flags)
  auto_switch_pane = true,         -- Auto switch to Claude pane
  auto_reload_buffers = true,      -- Auto reload buffers when focus returns to Neovim
  debug = false,                   -- Enable debug logging
})
```

Note: 
- **`claude_code_cmd`**: Should only contain the command name/path (e.g., `"claude"` or `"/path/to/claude"`), not flags. The plugin automatically adds appropriate flags.
- `<leader>cc` creates new Claude instances with `claude --continue` when no instance exists
- `<leader>cn` always creates new Claude instances with `claude` (no flags)

## How It Works

The plugin creates a seamless workflow between Neovim and Claude Code running in tmux:

1. When triggered, the plugin captures your current code context (file path, git root, cursor position, and optionally selected code)
2. It uses tmux commands to detect any existing Claude Code instances in the same git repository
   - Performs strict verification to ensure only actual Claude Code instances are detected
   - Uses multiple detection methods including command name, process information, and pane content
   - Shows detection method in the selection menu for transparency
   - Automatically renames windows running Claude to "claude" for consistent identification
3. If multiple instances exist, a clean table-formatted selection menu is presented
4. If no instances exist, it creates a new tmux window running Claude Code
   - Uses sophisticated pane tracking to ensure reliable operation
   - Implements retry mechanisms for tmux operations that might fail initially
   - Verifies created panes actually exist before attempting to use them
   - Includes fallback methods if the primary approach encounters issues
   - Shows an animated loading indicator during Claude instance startup
5. The context is formatted as structured XML and sent to the Claude Code instance via tmux
   - Uses tmux buffers for reliable pasting
   - Includes retry logic for paste operations
6. If configured, your tmux focus automatically switches to the Claude Code pane for immediate interaction
   - Employs a multi-step approach to ensure reliable window and pane selection
   - Includes verification and fallback mechanisms for window switching
7. When you return to Neovim (FocusGained event), all buffers are automatically reloaded to reflect any changes made by Claude Code

This approach keeps both environments running independently while creating an efficient bridge between them, with extensive error handling and fallback mechanisms to ensure reliable operation.

## Usage

1. Press `<leader>cc` (or your configured keymap) in normal or visual mode to send context to an existing Claude Code instance.
2. Press `<leader>cn` (or your configured keymap_new) in normal or visual mode to create a new Claude Code instance and send context to it.
3. If multiple Claude Code instances are found in the same git repository when using `<leader>cc`, you'll be prompted to select one.
4. The plugin sends the file context to Claude Code and switches to that pane.
5. After interacting with Claude Code, when you switch back to Neovim, your buffers will automatically reload to reflect any changes.

In visual mode, only your selected code will be included in the XML context, helping Claude Code focus on the specific portion you need help with. This works for both `<leader>cc` and `<leader>cn`.

## Commands

- `:ClaudeCodeSend` - Send the current file context to Claude Code.
- `:ClaudeCodeNew` - Create a new Claude Code instance and send context (always uses plain `claude` command).
- `:ClaudeCodeReload` - Manually reload all Neovim buffers from disk.
- `:ClaudeCodeDebug` - Toggle debug mode for troubleshooting.
- `:ClaudeCodeShowLog` - Show the debug log in a split window.
- `:ClaudeCodeClearLog` - Clear the debug log file.

## XML Format

The plugin sends context to Claude Code in an XML format:

```xml
<context>
  <file_path>/path/to/file.lua</file_path>
  <git_root>/path/to/project</git_root>
  <line_number>42</line_number>
  <column_number>15</column_number>
  <selection>selected_text_here</selection>
  <file_content>full_file_content_here</file_content>
</context>
```

This format helps Claude Code understand the exact context of your code, making its responses more relevant and accurate.

## Architecture

The plugin uses a modular architecture for maintainability:

- `init.lua` - Main entry point with public API
- `lib/config.lua` - Configuration management and state tracking
- `lib/util.lua` - Utility functions for file and text operations
- `lib/tmux.lua` - Tmux interaction and Claude Code instance management
- `lib/context.lua` - Context generation and XML formatting
- `lib/debug.lua` - Debug logging functionality
- `lib/silent.lua` - Handles silent operations for better UX

## License

MIT