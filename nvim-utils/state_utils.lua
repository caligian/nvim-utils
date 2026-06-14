local path = require 'lua-utils.path_utils'
local types = require 'lua-utils.types'
local dict = require 'lua-utils.dict'

require 'nvim-utils.state'
require 'nvim-utils.buffer'
require 'nvim-utils.filetype'
require 'nvim-utils.autocmd'
require 'nvim-utils.buffer_group'

user_config.utils = {}
local utils = user_config.utils

function utils.setup_buffer_groups(overrides)
  buffer_group.utils.setup(overrides)
  --- Fix this
end

function utils.setup_settings(overrides)
  require('config.settings')
end

function utils.setup_keymaps(overrides)
  local config = require('config.keymap')
  if type(config) == 'table' then
    overrides = dict.merge(vim.deepcopy(overrides or {}), config)
    keymap.define(overrides)
  end
end

function utils.setup_autocmds(overrides)
  local config = require('config.autocmd')
  if type(config) == 'table' then
    overrides = dict.merge(vim.deepcopy(overrides), config)
    autocmd.define(config)
  end
end

function utils.setup_filetypes(overrides)
  filetype.utils.setup_builtin(overrides)
end

function utils.setup_plugins()
  require('config.lazy')
end

function utils.setup()
  utils.setup_filetypes()
  utils.setup_plugins()
  utils.setup_settings()
  utils.setup_autocmds()
  utils.setup_keymaps()
  utils.setup_buffer_groups()
end

function utils.on_exit(name, callback, opts)
  -- local opts_ = vim.deepcopy(opts)
  -- opts_.pattern = pattern
  -- opts = {pattern = pattern}
  -- user_config.default_augroup:add_autocmd(
  --   name, 'VimLeavePre', pattern, callback, opts
  -- )
end

return utils
