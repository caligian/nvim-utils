require 'lua-utils'

local path = require 'lua-utils.path_utils'
local dict = require 'lua-utils.dict'

require 'nvim-utils.state'
local nvim = require 'nvim-utils.nvim'
local buffer = require 'nvim-utils.buffer_utils'
local autocmd = require 'nvim-utils.autocmd'

require 'nvim-utils.filetype'
require 'nvim-utils.buffer_group'
require 'nvim-utils.command'
require 'nvim-utils.repl'
require 'nvim-utils.pkgs'
require 'nvim-utils.template'

user_config.utils = bless {}
local utils = user_config.utils

function utils.setup_buffer_groups(overrides)
  buffer_group.utils.setup(overrides)
  --- Fix this
end

function utils.setup_settings(overrides)
  --- Add overrides here too
  require('config.settings')
end

function utils.setup_commands(overrides)
  vim.api.nvim_create_user_command(
    'Messages', function(args)
      if args.args:match 'v' then
        vim.cmd('vsplit | wincmd l | b ' .. user_config.messages.buffer)
      else
        vim.cmd('split | wincmd j | b ' .. user_config.messages.buffer)
      end
    end, {
      nargs = '?',
      desc = "Show system packages",
      complete = function()
        return { "split", "vsplit" }
      end,
    }
  )

  overrides = overrides or {}
  local ok, config = pcall(require, 'config.command')
  if ok and is.table(config) then
    dict.mergef(config, overrides)
    command.define(config)
  end
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

function utils.setup_plugins(overrides)
  local plugins = require('nvim-utils.pkgs')
  plugins:setup(overrides)
end

function utils.setup_templates(overrides)
  user_config.template.setup(overrides)
end

function utils.setup()
  utils.setup_filetypes()
  utils.setup_plugins()
  utils.setup_settings()
  utils.setup_autocmds()
  utils.setup_keymaps()
  utils.setup_buffer_groups()
  utils.setup_templates()
  utils.setup_commands()
end

utils.setup()

return utils
