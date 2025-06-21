---@brief Context handling module
---
--- Functions for creating and formatting context data for Claude Code.

local M = {}
local util = require('claude-tmux-neovim.lib.util')
local config = require('claude-tmux-neovim.lib.config')

--- Create a context payload for sending to Claude
---@param opts table|nil Options including range information
---@return table|nil context Context information or nil if failed
function M.create_context(opts)
  -- Perform validation checks without disruptive notifications
  if not util.is_tmux_running() then
    -- More subtle notification - won't interrupt workflow
    vim.schedule(function()
      vim.notify("tmux is not running", vim.log.levels.WARN)
    end)
    return nil
  end

  -- Get current file path
  local file_path = vim.fn.expand('%:p')
  if file_path == "" then
    -- More subtle notification
    vim.schedule(function()
      vim.notify("No file open", vim.log.levels.WARN)
    end)
    return nil
  end
  
  -- Get git root
  local git_root = util.get_git_root()
  if not git_root then
    -- More subtle notification
    vim.schedule(function()
      vim.notify("Not in a git repository", vim.log.levels.WARN)
    end)
    return nil
  end
  
  -- Get cursor position
  local position = util.get_cursor_position()
  local line_num = position.line
  local col_num = position.column
  
  -- Get selection (from visual range or current line)
  local selection = ""
  
  -- Check if we have a range (visual selection)
  if opts and opts.range and opts.range > 0 then
    selection = util.get_selection_from_range(opts.line1, opts.line2)
  else
    -- No visual selection - include current line content
    selection = util.get_current_line(line_num)
  end
  
  -- Get file content
  local file_content = util.get_file_content()
  
  return {
    file_path = file_path,
    git_root = git_root,
    line_num = line_num,
    col_num = col_num,
    selection = selection,
    file_content = file_content
  }
end

--- Format context as XML
---@param context table The context information
---@return string xml The formatted XML
function M.format_context_xml(context)
  return string.format(
    config.get().xml_template,
    context.file_path,
    context.git_root,
    context.line_num,
    context.col_num,
    context.selection,
    context.file_content
  )
end

return M