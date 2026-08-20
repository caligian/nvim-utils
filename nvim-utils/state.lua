#!/usr/bin/env luajit

if user_config then
  return
end

local dict = require 'lua-utils.dict'
local path_utils = require 'lua-utils.path_utils'
local root_dir = vim.fn.stdpath('config')
local data_dir = vim.fn.stdpath('data')
local lua_dir = root_dir .. '/lua'
local config_dir = lua_dir .. '/config'
local filetype_dir = config_dir .. '/filetype'
local keymap_file = config_dir .. '/keymap.lua'
local autocmd_file = config_dir .. '/autocmd.lua'
local template_dir = root_dir .. '/templates'
local settings_file = root_dir .. '/settings.lua'
local messages_file = data_dir .. '/messages.txt'
local pkgs_dir = data_dir .. '/pkgs'

---@class user_config.theme
---@field [1] string
---@field before fun(self: user_config.theme)
---@field after fun(self: user_config.theme)

---@class user_config.telescope
---@field theme? table
---@field opts? table

---@class user_config.state.autocmd
---@field by_id table<number, autocmd>
---@field by_name table<string,autocmd>
---@field __index fun(self: user_config.state.autocmd, name: string|number): autocmd

---@class user_config.state.augroup
---@field by_id table<number, augroup>
---@field by_name table<string|number,augroup>
---@field __index fun(self: user_config.state.augroup, name: string|number): autocmd

---@class user_config.state.terminal
---@field by_id table<number,terminal>
---@field by_pid table<number,terminal>

---@class user_config.state
---@field keymap table<string,keymap>
---@field autocmd user_config.state.autocmd
---@field augroup user_config.state.augroup
---@field command table<string,command>
---@field filetype table<string,filetype>
---@field buffer_group table<string,buffer_group>
---@field workspace table<string|number,string>
---@field terminal table<string,terminal>
---@field shell? terminal

---@class user_config.path.file
---@field autocmd string
---@field keymap string
---@field settings string
---@field messages string

---@class user_config.path.dir
---@field config string
---@field data string
---@field filetype string
---@field lua string
---@field pkgs string
---@field root string
---@field template string

---@class user_config.path
---@field autocmd_file string
---@field config_dir string
---@field data_dir string
---@field filetype_dir string
---@field keymap_file string
---@field lua_dir string
---@field messages_file string
---@field pkgs_dir string
---@field root_dir string
---@field settings_file string
---@field template_dir string
---@field file user_config.path.file
---@field dir user_config.path.dir

---@class user_config.telescope
---@field theme table Theme options to pass to telescope constructors
---@field opts? table Rest of the options

---@class user_config.pkgs
---@field name string
---@field dir string
---@field repo string
---@field opts? table

---@class user_config.settings
---@field g table
---@field o table

---@class user_config.shell
---@field cmd string
---@field terminal? terminal

---@class user_config
---@field state user_config.state
---@field path user_config.path
---@field telescope user_config.telescope
---@field shell_command string (default: bash)
---@field pkgs user_config.pkgs
---@field settings user_config.settings

---@type user_config
---@overload fun(...: string|number): any
user_config = refself {
  keymap = {},
  augroup = {},
  autocmd = {},
  filetype = {},
  buffer = {
    buffer_group = {},
    recent = {},
    messages = nil,
  },
  buffer_group = {},
  workspace = {},
  project = {},
  terminal = {},
  repl = { system = nil },
  shell = vim.env.shell,
  utils = { path = {} },
  pkgs = {},
  template = {},
  shell_command = 'bash',
}

---@type user_config.shell
user_config.shell = {
  cmd = vim.env.SHELL,
  terminal = nil
}

---@type user_config.path
user_config.path = {
  ---@type user_config.path.file
  file = {
    keymap = keymap_file,
    autocmd = autocmd_file,
    settings = settings_file,
    messages = messages_file,
  },

  ---@type user_config.path.dir
  dir = {
    root = root_dir,
    data = data_dir,
    lua = lua_dir,
    config = config_dir,
    filetype = filetype_dir,
    template = template_dir,
    pkgs = pkgs_dir,
  },

  root_dir = root_dir,
  data_dir = data_dir,
  lua_dir = lua_dir,
  config_dir = config_dir,
  filetype_dir = filetype_dir,
  template_dir = template_dir,
  keymap_file = keymap_file,
  autocmd_file = autocmd_file,
  settings_file = settings_file,
  pkgs_dir = pkgs_dir,
  messages_file = messages_file,
}

---@type user_config.state
user_config.state = refself {
  autocmd = { by_id = {}, by_name = {} },
  augroup = { by_id = {}, by_name = {} },
  terminal = { by_id = {}, by_pid = {} },
  keymap = {},
  command = {},
  filetype = {},
}

---@type user_config.telescope
user_config.telescope = refself {
  theme = { previewer = false },
  opts = {
    layout_config = {
      height = 0.5,
    }
  },
}

---@type user_config.pkgs
user_config.pkgs = refself {
  opts = {
    spec = { { import = "pkgs" }, },
    checker = { enabled = false },
    lazy = false,
    dir = user_config.path.dir.pkgs
  },
  name = 'lazy',
  repo = "https://github.com/folke/lazy.nvim",
}

---When called, call :before setting theme and :after after setting the theme
---@type user_config.theme
---@overload fun()
user_config.theme = refself {
  'modus',

  ---Run before theme is set
  ---@param self user_config.theme
  before = function(self)
    if self[1]:match 'light' then
      vim.o.background = 'light'
    else
      vim.o.background = 'dark'
    end


  end,

  ---Run after theme is set
  ---@param self user_config.theme
  after = function(self)
    if self[1]:match 'light' then
      vim.cmd.highlight('IndentLine guifg=#48494b')
      vim.cmd.highlight('IndentLineCurrent guifg=#777b7e')
    end
  end,

  ---Set theme
  ---@param self user_config.theme
  __call = function(self)
    self:before()
    vim.cmd.color(self[1])
    self:after()
    vim.cmd.color(self[1])
  end
}

refself(user_config)
refself(user_config.theme)
refself(user_config.state)

---@param ... string|number
---@return any
function user_config.get(...)
  local ks = { ... }
  local value = dict.get(user_config, ks, function()
    return nil
  end)
  value = as_value(value)
  return value
end

---@param ... string|number
---@return any
function user_config.state.get(...)
  local ks = { ... }
  local value = dict.get(user_config.state, ks, function()
    return nil
  end)
  value = as_value(value)
  return value
end

---@param ks (string|number)[]
---@param value any
function user_config.set(ks, value)
  value = as_value(value)
  ks = not is.pure_list(ks) and { ks } or ks
  dict.set(user_config, ks, value, true)
end

---@param ks (string|number)[]
---@param value any
function user_config.state.set(ks, value)
  value = as_value(value)
  ks = not is.pure_list(ks) and { ks } or ks
  dict.set(user_config.state, ks, value, true)
end

---@param ks (string|number)[]
---@param callback (fun(value: any): any)
---@param ifnil? (fun(value: any): any)
---@return any
function user_config.with(ks, callback, ifnil)
  local value = user_config.get(unpack(ks))
  value = as_value(value)

  if value ~= nil then
    return callback(value)
  elseif ifnil then
    return ifnil()
  end
end

---Query user_config table
---@param ... string|number
---@return any
function user_config:__call(...)
  return user_config.get(...)
end

---Query user_config.state
---@param ... string|number
---@return any
function user_config.state:__call(...)
  return user_config.state.get(...)
end

---@param ks (string|number)[]
---@param fn function
---@param ifnil? function
---@return any
function user_config.state.with(ks, fn, ifnil)
  local value = as_value(user_config.state(unpack(ks)))
  if value ~= nil then
    return fn(value)
  elseif ifnil then
    return ifnil()
  end
end

return user_config
