---@brief Error handling utilities
---
--- Centralized error handling and notification system.

local M = {}
local debug = require('claude-tmux-neovim.lib.debug')
local constants = require('claude-tmux-neovim.lib.constants')

--- Handle different types of errors consistently
---@param error_type string The type of error (e.g., "tmux", "git", "file", "config")
---@param message string The error message
---@param should_notify boolean Whether to show notification to user
---@param log_level number|nil The log level (defaults to ERROR)
function M.handle_error(error_type, message, should_notify, log_level)
  log_level = log_level or constants.LOG_LEVELS.ERROR
  
  -- Always log the error
  local full_message = string.format("[%s] %s", error_type:upper(), message)
  debug.log(full_message, log_level)
  
  -- Show notification if requested
  if should_notify then
    vim.schedule(function()
      vim.notify(message, log_level)
    end)
  end
end

--- Handle tmux-related errors
---@param message string The error message
---@param should_notify boolean Whether to show notification
function M.tmux_error(message, should_notify)
  M.handle_error("tmux", message, should_notify)
end

--- Handle git-related errors
---@param message string The error message
---@param should_notify boolean Whether to show notification
function M.git_error(message, should_notify)
  M.handle_error("git", message, should_notify)
end

--- Handle file-related errors
---@param message string The error message
---@param should_notify boolean Whether to show notification
function M.file_error(message, should_notify)
  M.handle_error("file", message, should_notify)
end

--- Handle configuration errors
---@param message string The error message
---@param should_notify boolean Whether to show notification
function M.config_error(message, should_notify)
  M.handle_error("config", message, should_notify)
end

--- Handle Claude instance creation errors
---@param message string The error message
---@param should_notify boolean Whether to show notification
function M.instance_error(message, should_notify)
  M.handle_error("instance", message, should_notify)
end

--- Handle warnings (non-critical issues)
---@param error_type string The type of warning
---@param message string The warning message
---@param should_notify boolean Whether to show notification
function M.handle_warning(error_type, message, should_notify)
  M.handle_error(error_type, message, should_notify, constants.LOG_LEVELS.WARN)
end

--- Handle silent errors (log only, no notification)
---@param error_type string The type of error
---@param message string The error message
function M.silent_error(error_type, message)
  M.handle_error(error_type, message, false)
end

--- Wrap function execution with error handling
---@param func function The function to execute
---@param error_type string The error type for any caught errors
---@param error_message string The error message prefix
---@param should_notify boolean Whether to notify on errors
---@return boolean success Whether the function executed successfully
function M.safe_execute(func, error_type, error_message, should_notify)
  local success, err = pcall(func)
  
  if not success then
    local full_message = error_message .. ": " .. tostring(err)
    M.handle_error(error_type, full_message, should_notify)
    return false
  end
  
  return true
end

--- Execute a function with retry logic and error handling
---@param func function The function to execute
---@param max_retries number Maximum number of retries
---@param error_type string The error type
---@param error_message string The error message prefix
---@param should_notify boolean Whether to notify on final failure
---@return boolean success Whether the function eventually succeeded
function M.retry_execute(func, max_retries, error_type, error_message, should_notify)
  for attempt = 1, max_retries do
    local success = M.safe_execute(func, error_type, 
      string.format("%s (attempt %d/%d)", error_message, attempt, max_retries), 
      false) -- Don't notify on individual attempts
    
    if success then
      return true
    end
    
    -- Wait before retrying (except on last attempt)
    if attempt < max_retries then
      vim.fn.system("sleep " .. (attempt * constants.TIMEOUTS.RETRY_BASE_DELAY))
    end
  end
  
  -- Final failure notification
  if should_notify then
    M.handle_error(error_type, 
      string.format("%s failed after %d attempts", error_message, max_retries), 
      true)
  end
  
  return false
end

--- Validate and handle common preconditions
---@param checks table Array of {condition, error_type, message, should_notify}
---@return boolean all_valid Whether all checks passed
function M.validate_preconditions(checks)
  for _, check in ipairs(checks) do
    local condition, error_type, message, should_notify = unpack(check)
    if not condition then
      M.handle_error(error_type, message, should_notify)
      return false
    end
  end
  return true
end

--- Common validation for tmux operations
---@return boolean valid Whether tmux environment is valid
function M.validate_tmux_environment()
  local util = require('claude-tmux-neovim.lib.util')
  
  return M.validate_preconditions({
    {util.is_tmux_running(), "tmux", "tmux is not running", true},
  })
end

--- Common validation for git operations
---@return boolean valid Whether git environment is valid
function M.validate_git_environment()
  local util = require('claude-tmux-neovim.lib.util')
  
  return M.validate_preconditions({
    {util.get_git_root() ~= nil, "git", "Not in a git repository", true},
  })
end

--- Common validation for file operations
---@return boolean valid Whether file environment is valid
function M.validate_file_environment()
  local file_path = vim.fn.expand('%:p')
  
  return M.validate_preconditions({
    {file_path ~= "", "file", "No file open", true},
  })
end

return M