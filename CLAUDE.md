# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Claude-tmux-neovim is a fast, minimal Neovim plugin that sends code context to Claude Code via tmux. It captures file path, line numbers, and selected text, formatting them as XML with @ file references that Claude Code can understand.

Repository: https://github.com/karlhepler/claude-tmux-neovim
License: MIT

## Architecture

The plugin has been completely rewritten for speed and simplicity:

- **Single file**: All logic in `lua/claude-tmux-neovim/init.lua` (~360 lines)
- **Fast detection**: Single shell pipeline finds Claude processes in <50ms
- **Direct operations**: No wrappers, retries, or complex verification
- **Minimal dependencies**: Just Neovim and tmux

## Core Workflow

1. **Capture context**: Get current/selected lines with line numbers
2. **Find Claude**: Use `ps aux | grep '\d\d claude'` to find processes
3. **Map to tmux**: Get parent PID to find tmux pane
4. **Filter by repo**: Only show instances in same git repository
5. **Send XML**: Format and paste via tmux buffers
6. **Switch focus**: Move to Claude pane after pasting

## Key Commands

- `<leader>cc` - Send to existing Claude or create with `--continue`
- `<leader>cn` - Always create new Claude instance (no flags)

## Development

### Testing Changes

1. Make changes to `init.lua`
2. Restart Neovim or `:source %`
3. Test both keymaps manually

### Key Functions

- `find_claude_instances()` - Detect Claude processes and map to tmux
- `get_selection()` - Get current line or visual selection
- `create_context()` - Format XML with @ file references
- `send_to_claude()` - Paste via tmux and switch focus

### XML Format

```xml
<context>
  <file>@/absolute/path/to/file.lua</file>
  <start_line>5</start_line>
  <end_line>8</end_line>
  <selection>
Line 5 content
Line 6 content
Line 7 content
Line 8 content
  </selection>
</context>
```

## Performance

- Claude detection: ~20ms
- Context creation: ~5ms
- Tmux operations: ~10ms
- **Total: <50ms for existing instance**

## Testing Checklist

1. **Basic Operations**
   - [ ] `<leader>cc` with no instances (creates with --continue)
   - [ ] `<leader>cc` with one instance (uses it)
   - [ ] `<leader>cc` with multiple instances (shows picker)
   - [ ] `<leader>cn` (always creates new)

2. **Visual Mode**
   - [ ] Select lines and use `<leader>cc`
   - [ ] Select lines and use `<leader>cn`

3. **Edge Cases**
   - [ ] Not in git repository
   - [ ] Claude showing menu
   - [ ] Claude instance closed during operation

## Implementation Notes

- Claude detection uses pattern `\d\d claude` (timestamp before command)
- Parent PID mapping needed because tmux shows shell PID, not Claude PID
- Instance picker shows tmux pane IDs for verification
- Ready check only verifies input box exists (│ character)