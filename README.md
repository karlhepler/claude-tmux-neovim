# claude-tmux-neovim

A Neovim plugin that integrates with Claude Code via tmux, allowing you to send file context to Claude Code instances.

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
vim.opt.rtp:prepend("~/github.com/karlhepler/claude-tmux-neovim")
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
  <selection>
    selected_text_here
  </selection>
  <file_content>
    full_file_content_here
  </file_content>
</context>

Please review this code context.
```

## License

MIT