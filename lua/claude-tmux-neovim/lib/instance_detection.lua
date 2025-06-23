---@brief Claude instance detection utilities
---
--- Functions for detecting and verifying Claude Code instances in tmux.

local M = {}
local debug = require('claude-tmux-neovim.lib.debug')
local tmux_cmd = require('claude-tmux-neovim.lib.tmux_commands')
local constants = require('claude-tmux-neovim.lib.constants')
local config = require('claude-tmux-neovim.lib.config')

--- Detect Claude instances using standard methods
---@param git_root string The git repository root path
---@param current_session string The current tmux session name
---@return table[] instances Array of detected instances
function M.detect_standard_instances(git_root, current_session)
  debug.log("Starting standard detection for Claude instances in git root: " .. git_root)
  
  local result = tmux_cmd.list_panes(constants.TMUX.PANE_FORMAT)
  if not result.success then
    debug.log("Failed to list tmux panes", vim.log.levels.WARN)
    return {}
  end
  
  local instances = {}
  local claude_code_cmd = config.get().claude_code_cmd
  
  for _, line in ipairs(result.panes) do
    local instance = M.parse_pane_line(line)
    if instance and M.is_potential_claude_instance(instance, claude_code_cmd) then
      if M.verify_claude_instance_in_git_root(instance, git_root) then
        instance.is_current_session = (instance.session == current_session)
        table.insert(instances, instance)
      end
    end
  end
  
  return instances
end

--- Detect Claude instances using aggressive fallback methods
---@param git_root string The git repository root path
---@param current_session string The current tmux session name
---@return table[] instances Array of detected instances
function M.detect_aggressive_instances(git_root, current_session)
  debug.log("Starting aggressive fallback detection")
  
  local result = tmux_cmd.list_panes(constants.TMUX.PANE_FORMAT)
  if not result.success then
    return {}
  end
  
  local instances = {}
  
  for _, line in ipairs(result.panes) do
    local instance = M.parse_pane_line(line)
    if instance and instance.pane_path == git_root then
      if M.aggressive_claude_verification(instance) then
        instance.is_current_session = (instance.session == current_session)
        instance.detection_method = constants.DETECTION_METHODS.AUTO
        table.insert(instances, instance)
      end
    end
  end
  
  return instances
end

--- Parse a pane line into instance components
---@param line string The pane line from tmux list-panes
---@return table|nil instance Parsed instance or nil if invalid
function M.parse_pane_line(line)
  local pane_id, session, window_name, window_idx, pane_idx, command, pane_path = 
    line:match("(%%[0-9]+) ([^ ]+) ([^ ]+) ([0-9]+) ([0-9]+) ([^ ]+) (.*)")
  
  if not pane_id or not command or not pane_path then
    debug.log("Failed to parse pane information from line", vim.log.levels.WARN)
    return nil
  end
  
  return {
    pane_id = pane_id,
    session = session,
    window_name = window_name,
    window_idx = window_idx,
    pane_idx = pane_idx,
    command = command,
    pane_path = pane_path
  }
end

--- Check if instance is potentially Claude using basic criteria
---@param instance table The parsed instance
---@param claude_code_cmd string The Claude command to match
---@return boolean is_potential Whether this could be Claude
function M.is_potential_claude_instance(instance, claude_code_cmd)
  -- Method 1: Check window name first
  if instance.window_name:lower() == constants.TMUX.CLAUDE_WINDOW_NAME then
    return true
  end
  
  -- Method 2: Check command name directly
  if instance.command == claude_code_cmd then
    return true
  end
  
  -- Method 3: Check if command path ends with claude command
  if instance.command:match("/" .. claude_code_cmd .. "$") then
    return true
  end
  
  -- Method 4: Check Node.js processes that might be Claude
  if instance.command == "node" or instance.command == "node.js" or instance.command:match("node") then
    return true
  end
  
  return false
end

--- Verify that an instance is actually Claude and in the correct git root
---@param instance table The instance to verify
---@param git_root string The expected git root
---@return boolean is_claude Whether this is a verified Claude instance
function M.verify_claude_instance_in_git_root(instance, git_root)
  -- Must be in exact git root
  if instance.pane_path ~= git_root then
    return false
  end
  
  return M.verify_claude_instance(instance)
end

--- Verify that an instance is actually running Claude
---@param instance table The instance to verify
---@return boolean is_claude Whether this is Claude
function M.verify_claude_instance(instance)
  debug.log("Verifying Claude instance: " .. instance.pane_id)
  
  -- Method 1: Check for Claude prompt pattern (most reliable)
  if tmux_cmd.has_claude_prompt(instance.pane_id) then
    debug.log("Confirmed Claude by prompt pattern: " .. instance.pane_id)
    instance.detection_method = constants.DETECTION_METHODS.PROMPT
    return true
  end
  
  -- Method 2: Check window name
  if instance.window_name:lower() == constants.TMUX.CLAUDE_WINDOW_NAME then
    debug.log("Confirmed Claude by window name: " .. instance.pane_id)
    instance.detection_method = constants.DETECTION_METHODS.NAME
    return true
  end
  
  -- Method 3: Check process command line
  local process_result = tmux_cmd.get_pane_process(instance.pane_id)
  if process_result.success then
    if process_result.output:lower():match("claude") or process_result.output:match("anthropic") then
      debug.log("Confirmed Claude by process command: " .. instance.pane_id)
      instance.detection_method = constants.DETECTION_METHODS.PROC
      return true
    end
  end
  
  -- Method 4: Command-based detection
  local claude_code_cmd = config.get().claude_code_cmd
  if instance.command == claude_code_cmd then
    instance.detection_method = constants.DETECTION_METHODS.CMD
    return true
  elseif instance.command:match("/" .. claude_code_cmd .. "$") then
    instance.detection_method = constants.DETECTION_METHODS.PATH
    return true
  elseif instance.command:match("node") then
    instance.detection_method = constants.DETECTION_METHODS.NODE
    return true
  end
  
  return false
end

--- Aggressive verification for fallback detection
---@param instance table The instance to verify
---@return boolean is_claude Whether this is Claude
function M.aggressive_claude_verification(instance)
  debug.log("AGGRESSIVE MODE: Checking pane: " .. instance.pane_id)
  
  -- Skip obvious non-Claude processes
  if instance.command == "nvim" or instance.command == "vim" or instance.command == "vi" then
    return false
  end
  
  -- Use all verification methods
  if M.verify_claude_instance(instance) then
    return true
  end
  
  -- Additional aggressive checks could go here
  return false
end

--- Add display information to an instance
---@param instance table The instance to enhance
---@return table instance The instance with display information
function M.add_display_info(instance)
  -- Get last conversation line for context
  local last_line_cmd = string.format(
    [[tmux capture-pane -p -t %s | grep -B 1 -m 1 -e '╭─\{1,\}╮' | grep -v '╭─\{1,\}╮' | grep -v '^$' | tail -n 1]],
    instance.pane_id
  )
  local last_line_result = tmux_cmd.execute(last_line_cmd, "get last conversation line")
  
  if last_line_result.success and last_line_result.output ~= "" then
    local last_line = last_line_result.output
    if #last_line > constants.LIMITS.DISPLAY_NAME_LENGTH then
      last_line = string.sub(last_line, 1, constants.LIMITS.LAST_LINE_TRUNCATE) .. "..."
    end
    instance.last_line = last_line
  end
  
  -- Determine display name
  local display_name
  if instance.last_line and instance.last_line ~= "" then
    display_name = instance.last_line
  elseif instance.window_name and instance.window_name ~= "" then
    display_name = instance.window_name
  else
    display_name = "Claude instance"
  end
  
  instance.display = string.format("%s: %s.%s (%s) %s", 
    instance.session, 
    instance.window_idx, 
    instance.pane_idx,
    display_name,
    instance.detection_method or constants.DETECTION_METHODS.OTHER
  )
  
  return instance
end

--- Rename tmux window to "claude" if needed
---@param instance table The instance to potentially rename
---@return boolean was_renamed Whether the window was renamed
function M.rename_window_if_needed(instance)
  if instance.window_name:lower() ~= constants.TMUX.CLAUDE_WINDOW_NAME then
    -- Verify this is actually Claude before renaming
    if tmux_cmd.has_claude_prompt(instance.pane_id) then
      debug.log("Renaming window from '" .. instance.window_name .. "' to 'claude' for consistency")
      local rename_result = tmux_cmd.rename_window(instance.session, instance.window_idx, constants.TMUX.CLAUDE_WINDOW_NAME)
      if rename_result.success then
        instance.window_name = constants.TMUX.CLAUDE_WINDOW_NAME
        instance.detection_method = constants.DETECTION_METHODS.RENAMED
        return true
      end
    end
  end
  return false
end

return M