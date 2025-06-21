---@brief Configuration module
---
--- Handles configuration management for the claude-tmux-neovim plugin.

local M = {}

-- Default configuration
M.defaults = {
  keymap = "<leader>cc", -- Default keymap to trigger sending context
  claude_code_cmd = "claude", -- Command to start Claude Code
  auto_switch_pane = true, -- Automatically switch to tmux pane after sending
  remember_choice = true, -- Remember chosen Claude Code instance per git repo
  debug = false, -- Enable debug logging
  
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
  config = {}, -- Merged config
  remembered_instances = {} -- Stored tmux instances by git root
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

--- Reset all remembered instances
function M.reset_instances()
  M.state.remembered_instances = {}
  -- Use scheduled notification for less disruptive UX
  vim.schedule(function()
    vim.notify("Reset all remembered Claude Code instances", vim.log.levels.INFO)
  end)
end

--- Get remembered instance for git root
---@param git_root string The git repository root path
---@return table|nil remembered_instance The remembered instance or nil
function M.get_remembered_instance(git_root)
  return M.state.remembered_instances[git_root]
end

--- Set remembered instance for git root
---@param git_root string The git repository root path
---@param instance table The Claude Code instance to remember
function M.set_remembered_instance(git_root, instance)
  M.state.remembered_instances[git_root] = instance
end

--- Clear remembered instance for git root
---@param git_root string The git repository root path
function M.clear_remembered_instance(git_root)
  M.state.remembered_instances[git_root] = nil
end

return M