-- Plugin entry point for claude-tmux-neovim

if vim.g.loaded_claude_tmux_neovim then
  return
end
vim.g.loaded_claude_tmux_neovim = true

-- Forward declarations for autocommands are in init.lua
-- The plugin is fully initialized when setup() is called