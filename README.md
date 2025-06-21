# claude-tmux-neovim

A Neovim plugin that seamlessly integrates with Claude Code via tmux, allowing you to send rich code context to Claude Code instances with a single keystroke.

## Why use this plugin?

- **Streamlined workflow**: Instantly send code context to Claude Code without leaving your editor
- **Rich context sharing**: Automatically includes file path, git root, cursor position, and optional selections
- **Seamless integration**: Works within your existing tmux sessions and git workflow
- **Smart instance management**: Detects existing Claude Code instances or creates new ones as needed

This plugin acts as a bridge between your Neovim editor and Claude Code running in tmux panes, enabling a smooth AI-assisted coding experience while maintaining your preferred environment.

## Architecture

The plugin uses a modular architecture for maintainability:

- `init.lua` - Main entry point with public API
- `lib/config.lua` - Configuration management
- `lib/util.lua` - Utility functions
- `lib/tmux.lua` - Tmux interaction
- `lib/context.lua` - Context generation and formatting

## Features

- Press `<leader>cc` to send context to Claude Code
- Works with visual selections
- Git repository isolation - only shows Claude Code instances in the same git repository
- Smart instance management:
  - Detects existing Claude Code instances in the correct git root
  - Creates new instances if none exist
  - Remembers choice per git repository
- Automatically switches to Claude Code pane after sending context
- Sends rich context in XML format optimized for LLMs

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
  keymap = "<leader>cc",           -- Key binding for trigger
  claude_code_cmd = "claude",      -- Command to start Claude Code
  auto_switch_pane = true,         -- Auto switch to Claude pane
  remember_choice = true,          -- Remember instance per git repo
})
```

## How It Works

The plugin creates a seamless workflow between Neovim and Claude Code running in tmux:

1. When triggered, the plugin captures your current code context (file path, git root, cursor position, and optionally selected code)
2. It uses tmux commands to detect any existing Claude Code instances in the same git repository
3. If no instances exist, it creates a new tmux window running Claude Code
4. The context is formatted as structured XML and sent to the Claude Code instance via tmux
5. If configured, your tmux focus automatically switches to the Claude Code pane for immediate interaction

This approach keeps both environments running independently while creating an efficient bridge between them.

## Usage

1. Press `<leader>cc` (or your configured keymap) in normal or visual mode.
2. If multiple Claude Code instances are found in the same git repository, you'll be prompted to select one.
3. The plugin sends the file context to Claude Code and switches to that pane.

Visual mode will include the selection in the XML context.

## Commands

- `:ClaudeCodeSend` - Send the current file context to Claude Code.
- `:ClaudeCodeReset` - Reset all remembered Claude Code instances.
- `:ClaudeCodeResetGit` - Reset the remembered Claude Code instance for the current git repository.

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

## License

MIT