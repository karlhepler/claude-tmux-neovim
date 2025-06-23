---@brief Configuration module
---
--- Handles configuration management for the claude-tmux-neovim plugin.

local M = {}

-- Default configuration
M.defaults = {
  keymap = "<leader>cc", -- Default keymap to trigger sending context
  keymap_new = "<leader>cn", -- Default keymap to create new Claude Code instance
  claude_code_cmd = "claude --continue", -- Command to start Claude Code with continue flag
  auto_switch_pane = true, -- Automatically switch to tmux pane after sending
  debug = false, -- Enable debug logging
  auto_reload_buffers = true, -- Automatically reload buffers when returning from Claude Code
  
  -- XML template for sending context
  xml_template = [[
<context>
  <file_path>%s</file_path>
  <git_root>%s</git_root>
  <line_number>%s</line_number>
  <column_number>%s</column_number>
  <selection>%s</selection>
  <file_content>%s</file_content>
</context>]],
}

-- Internal state
M.state = {
  config = {} -- Merged config
}

--- Apply user configuration
---@param user_config table|nil User configuration options
function M.setup(user_config)
  -- Merge default config with user config
  M.state.config = vim.tbl_deep_extend("force", M.defaults, user_config or {})
end

--- Get current configuration
---@return table Current configuration
function M.get()
  return M.state.config
end





return M