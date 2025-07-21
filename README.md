# claude-tmux-neovim

A fast, minimal Neovim plugin that sends code context to Claude Code via tmux with a single keystroke.

## Overview

Press `<leader>cc` in Neovim to instantly send your code to Claude. The plugin:
- Captures current/selected lines with line numbers
- Finds Claude instances in the same git repo
- Sends context as XML with @ file references
- Switches focus to Claude for immediate interaction

For a fresh Claude session, use `<leader>cn` instead.

## Features

- **< 50ms response time** - Nearly instant operation
- **Smart instance detection** - Reliably finds all Claude processes
- **Git-aware** - Only shows Claude instances in the same repository
- **Visual mode support** - Send selected lines or current line
- **Instance picker** - Choose between multiple Claude instances or create new
- **Auto-switch focus** - Moves to Claude pane after sending

## Requirements

- Neovim 0.7.0+
- tmux
- Claude Code CLI
- Git

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "karlhepler/claude-tmux-neovim",
  config = function()
    require("claude-tmux-neovim").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "karlhepler/claude-tmux-neovim",
  config = function()
    require("claude-tmux-neovim").setup()
  end
}
```

## Configuration

```lua
require("claude-tmux-neovim").setup({
  send_keymap = "<leader>cc",  -- Send to existing or create with --continue
  new_keymap = "<leader>cn",   -- Always create new instance (no flags)
})
```

## Usage

1. **Normal mode**: Press `<leader>cc` to send current line
2. **Visual mode**: Select lines and press `<leader>cc` to send selection
3. **New instance**: Press `<leader>cn` to create fresh Claude session

The plugin sends this XML format to Claude:

```xml
<context>
  <file>relative/path/to/file.lua</file>
  <start_line>5</start_line>
  <end_line>8</end_line>
  <selection>
Line 5 content
Line 6 content
Line 7 content
Line 8 content
  </selection>
  <file_content>
Full file contents here...
  </file_content>
</context>
```

The file path is shown relative to Claude's working directory, and the full file contents are included for context.

## How It Works

1. **Detect Claude**: Uses robust pattern matching to find all Claude processes
2. **Map to tmux**: Checks both parent PID and process PID for tmux pane mapping
3. **Filter by repo**: Shows only instances in the same git repository
4. **Send context**: Formats XML and pastes via tmux buffers
5. **Switch focus**: Automatically moves to Claude pane

When multiple instances exist, you'll see a picker like:
```
Select Claude instance:
1. %0 (0:0.0) - /path/to/repo
2. %15 (session:2.1) - /path/to/repo/src
3. Create new Claude instance
```

## License

MIT