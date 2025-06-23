---@brief Context handling module
---
--- Functions for creating and formatting context data for Claude Code.

local M = {}
local util = require('claude-tmux-neovim.lib.util')
local config = require('claude-tmux-neovim.lib.config')
local error_handler = require('claude-tmux-neovim.lib.error_handler')

--- Create a context payload for sending to Claude
---@param opts table|nil Options including range information
---@return table|nil context Context information or nil if failed
function M.create_context(opts)
  -- Validate environment prerequisites
  if not error_handler.validate_tmux_environment() then
    return nil
  end
  
  if not error_handler.validate_file_environment() then
    return nil
  end
  
  if not error_handler.validate_git_environment() then
    return nil
  end

  -- Get current file path (already validated above)
  local file_path = vim.fn.expand('%:p')
  
  -- Get git root (already validated above)
  local git_root = util.get_git_root()
  
  -- Get cursor position
  local position = util.get_cursor_position()
  local line_num = position.line
  local col_num = position.column
  
  -- Get selection (from visual range or current line)
  local selection = ""
  
  -- If we were provided with explicit selection text, use it
  if opts and opts.selection_text and opts.selection_text ~= "" then
    selection = opts.selection_text
  -- Check if we have a range (visual selection)
  elseif opts and opts.range and opts.range > 0 then
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