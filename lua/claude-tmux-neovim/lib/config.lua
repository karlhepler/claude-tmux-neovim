---@brief Configuration module
---
--- Handles configuration management for the claude-tmux-neovim plugin.

local M = {}

-- Default configuration
M.defaults = {
  keymap = "<leader>cc", -- Default keymap to trigger sending context
  keymap_new = "<leader>cn", -- Default keymap to create new Claude Code instance
  claude_code_cmd = "claude", -- Command to start Claude Code (path only, no flags)
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

--- Validate configuration values
---@param config table Configuration to validate
---@return boolean valid Whether configuration is valid
---@return string|nil error_message Error message if invalid
function M.validate(config)
  -- Validate claude_code_cmd
  if not config.claude_code_cmd or config.claude_code_cmd == "" then
    return false, "claude_code_cmd must be specified and non-empty"
  end
  
  -- Validate that claude_code_cmd doesn't contain flags
  if config.claude_code_cmd:match("%s%-%-") then
    return false, "claude_code_cmd should only contain the command/path, not flags"
  end
  
  -- Validate keymap format
  if config.keymap and type(config.keymap) ~= "string" then
    return false, "keymap must be a string"
  end
  
  if config.keymap_new and type(config.keymap_new) ~= "string" then
    return false, "keymap_new must be a string"
  end
  
  -- Validate boolean options
  local boolean_options = {"auto_switch_pane", "debug", "auto_reload_buffers"}
  for _, option in ipairs(boolean_options) do
    if config[option] ~= nil and type(config[option]) ~= "boolean" then
      return false, option .. " must be a boolean"
    end
  end
  
  -- Validate XML template
  if config.xml_template and type(config.xml_template) ~= "string" then
    return false, "xml_template must be a string"
  end
  
  return true, nil
end

--- Apply user configuration
---@param user_config table|nil User configuration options
function M.setup(user_config)
  -- Merge default config with user config
  local merged_config = vim.tbl_deep_extend("force", M.defaults, user_config or {})
  
  -- Validate the merged configuration
  local valid, error_message = M.validate(merged_config)
  if not valid then
    error("Invalid configuration: " .. error_message)
  end
  
  M.state.config = merged_config
end

--- Get current configuration
---@return table Current configuration
function M.get()
  return M.state.config
end





return M