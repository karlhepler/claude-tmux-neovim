---@brief Constants and configuration values
---
--- Central location for all constants used throughout the plugin.

local M = {}

-- Timeouts and delays
M.TIMEOUTS = {
  MAX_WAIT_CYCLES = 6,        -- Maximum loading cycles (1.8s total)
  CYCLE_DELAY = 0.3,          -- Delay between loading cycles
  NEW_INSTANCE_DELAY = 1.0,   -- Delay before sending to new instances
  RETRY_BASE_DELAY = 0.5,     -- Base delay for retries
  PANE_SWITCH_DELAY = 0.3,    -- Delay before switching to new panes
}

-- Tmux-related constants
M.TMUX = {
  BUFFER_NAME = "claude_context",           -- Buffer name for context data
  CLAUDE_WINDOW_NAME = "claude",            -- Standard window name for Claude instances
  LOADING_WINDOW_PREFIX = "claude loading", -- Prefix for loading window names
  PANE_FORMAT = "#{pane_id} #{session_name} #{window_name} #{window_index} #{pane_index} #{pane_current_command} #{pane_current_path}",
  PANE_INFO_FORMAT = "#{window_name}|#{pane_title}|#{pane_current_command}|#{pane_current_path}",
}

-- Pattern matching
M.PATTERNS = {
  CLAUDE_PROMPT = "╭─\\{1,\\}╮",      -- Claude's distinctive prompt pattern
  CLAUDE_PROMPT_WITH_CURSOR = "│ >", -- Claude prompt with cursor
  ERROR_PATTERNS = "failed\\|authentication failed\\|command not found",
}

-- Detection methods for Claude instances
M.DETECTION_METHODS = {
  CMD = "[cmd]",        -- Direct command match
  PATH = "[path]",      -- Path-based command match  
  NODE = "[node]",      -- Node.js process
  PROMPT = "[prompt]",  -- Claude prompt pattern
  PROC = "[proc]",      -- Process command line
  NAME = "[name]",      -- Window name
  RENAMED = "[renamed]", -- Window was renamed
  OTHER = "[other]",    -- Other detection method
  AUTO = "[auto]",      -- Aggressive fallback
  NEW = "[new]",        -- Newly created instance
  FAST = "[fast]",      -- Fast search result
}

-- Loading indicators (spinning animation)
M.LOADING_INDICATORS = { "⣾", "⣽", "⣻", "⢿", "⣯", "⣷" }

-- Retry configuration
M.RETRY = {
  MAX_ATTEMPTS = 3,     -- Maximum retry attempts for operations
  PASTE_RETRIES = 3,    -- Maximum retries for paste operations
}

-- Table formatting for instance selection
M.TABLE = {
  WIDTH = 90,
  COLUMN_WIDTHS = {3, 12, 8, 6, 10, 45}, -- Column widths for selection table
  SEPARATOR_CHAR = "-",
  BORDER_CHAR = "+",
  COLUMN_CHAR = "|",
}

-- Log levels mapping
M.LOG_LEVELS = {
  ERROR = vim.log.levels.ERROR,
  WARN = vim.log.levels.WARN,
  INFO = vim.log.levels.INFO,
  DEBUG = vim.log.levels.DEBUG,
}

-- Command line arguments
M.CLAUDE_ARGS = {
  CONTINUE = "--continue",  -- Continue flag for Claude
}

-- File path limits
M.LIMITS = {
  DISPLAY_NAME_LENGTH = 40,     -- Max length for display names
  PREVIEW_LENGTH = 60,          -- Max length for pane previews
  LAST_LINE_TRUNCATE = 37,      -- Truncate point for last lines
}

return M