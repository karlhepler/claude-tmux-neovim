---@brief Utility functions
---
--- Common utility functions for the claude-tmux-neovim plugin.

local M = {}

--- Check if tmux is running
---@return boolean is_running
function M.is_tmux_running()
  -- First check TMUX environment variable (most reliable)
  if vim.env.TMUX and vim.env.TMUX ~= "" then
    return true
  end
  
  -- Fallback to command check
  local result = vim.fn.system('which tmux && tmux info >/dev/null 2>&1 && echo "true" || echo "false"')
  return vim.trim(result) == "true"
end

--- Get git root directory of current file
---@return string|nil git_root
function M.get_git_root()
  local file_dir = vim.fn.expand('%:p:h')
  local cmd = 'cd ' .. vim.fn.shellescape(file_dir) .. ' && git rev-parse --show-toplevel 2>/dev/null'
  local git_root = vim.fn.system(cmd)
  
  if vim.v.shell_error ~= 0 then
    return nil
  end
  
  return vim.trim(git_root)
end

--- Get current line content
---@param line_num number The line number to get
---@return string line_content
function M.get_current_line(line_num)
  if line_num <= 0 or line_num > vim.api.nvim_buf_line_count(0) then
    return ""
  end
  
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
  return line
end

--- Get current file content
---@return string file_content
function M.get_file_content()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, '\n')
end

--- Get cursor position information
---@return table position with line and column
function M.get_cursor_position()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  return {
    line = cursor_pos[1], -- 1-based line number
    column = cursor_pos[2] + 1 -- Convert 0-based column to 1-based
  }
end

--- Get selection content from range
---@param start_line number
---@param end_line number
---@return string selection
function M.get_selection_from_range(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  return table.concat(lines, '\n')
end

return M