# claude-tmux-neovim

A Neovim plugin that seamlessly integrates with Claude Code via tmux, allowing you to send rich code context to Claude Code instances with a single keystroke.

## Why use this plugin?

- **Streamlined workflow**: Instantly send code context to Claude Code without leaving your editor
- **Rich context sharing**: Automatically includes file path, git root, cursor position, and optional selections
- **Seamless integration**: Works within your existing tmux sessions and git workflow
- **Smart instance management**: Detects existing Claude Code instances or creates new ones as needed
- **Automatic file reloading**: When returning to Neovim from Claude Code, files are automatically reloaded to reflect any changes

This plugin acts as a bridge between your Neovim editor and Claude Code running in tmux panes, enabling a smooth AI-assisted coding experience while maintaining your preferred environment.

## Features

- Press `<leader>cc` to send context to Claude Code (uses `claude --continue` when auto-creating instances)
- Press `<leader>cn` to create a new Claude Code instance and send context (always uses plain `claude` without flags)
- Works with visual selections for more targeted assistance
- Git repository isolation - only shows Claude Code instances in the same git repository
- Smart instance management:
  - Detects existing Claude Code instances in the correct git root with strict verification
  - Shows detection method in selection menu ([cmd], [node], [prompt], [renamed], etc.)
  - Automatically renames tmux windows to "claude" for consistency
  - Creates new instances if none exist
  - Remembers choice per git repository
- Automatically switches to Claude Code pane after sending context
- Automatically reloads Neovim buffers when focus returns from Claude Code
- Sends rich context in XML format optimized for LLMs
- Debug mode for troubleshooting with detailed logging

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

### Add to runtime path

Add the plugin to your runtime path in your Neovim config:

```lua
-- Add the plugin to runtime path
vim.opt.rtp:prepend("~/path/to/claude-tmux-neovim")
```

## Configuration

Add this to your Neovim config:

```lua
require("claude-tmux-neovim").setup({
  keymap = "<leader>cc",           -- Key binding for sending context
  keymap_new = "<leader>cn",       -- Key binding for creating new Claude instance
  claude_code_cmd = "claude --continue", -- Command to start Claude Code (with continue flag)
  auto_switch_pane = true,         -- Auto switch to Claude pane
  remember_choice = true,          -- Remember instance per git repo
  auto_reload_buffers = true,      -- Auto reload buffers when focus returns to Neovim
  debug = false,                   -- Enable debug logging
})
```

## How It Works

The plugin creates a seamless workflow between Neovim and Claude Code running in tmux:

1. When triggered, the plugin captures your current code context (file path, git root, cursor position, and optionally selected code)
2. It uses tmux commands to detect any existing Claude Code instances in the same git repository
   - Performs strict verification to ensure only actual Claude Code instances are detected
   - Uses multiple detection methods including command name, process information, and pane content
   - Shows detection method in the selection menu for transparency
3. If multiple instances exist, a clean table-formatted selection menu is presented
4. If no instances exist, it creates a new tmux window running Claude Code
5. The context is formatted as structured XML and sent to the Claude Code instance via tmux
6. If configured, your tmux focus automatically switches to the Claude Code pane for immediate interaction
7. When you return to Neovim (FocusGained event), all buffers are automatically reloaded to reflect any changes made by Claude Code

This approach keeps both environments running independently while creating an efficient bridge between them.

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
- `:ClaudeCodeReset` - Reset all remembered Claude Code instances.
- `:ClaudeCodeResetGit` - Reset the remembered Claude Code instance for the current git repository.
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