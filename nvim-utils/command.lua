#!/usr/bin/env luajit

local lutils = require 'lua-utils'
local arguments = require 'lua-utils.validate'
local types = require 'lua-utils.types'
local is = require 'lua-utils.is'
local list = require 'lua-utils.list'
local dict = require 'lua-utils.dict'

local make_command = vim.api.nvim_create_user_command
local rm_command = vim.api.nvim_del_user_command
local buf_make_command = vim.api.nvim_buf_create_user_command
local buf_rm_command = vim.api.nvim_buf_del_user_command

require 'nvim-utils.state'
require 'nvim-utils.buffer'

---@class command.opts
---@field nargs? number|string
---@field complete? string
---@field count? number|string|boolean
---@field addr? string
---@field bang? boolean
---@field bar? boolean
---@field register? boolean
---@field keepscript? boolean

---@class command.shape : command.opts
---@overload fun(name: string, cmd: string|function, opts?: command.opts)

---@class command : command.shape
command = class 'command'

---Arguments validator for command options
command.opts_validator = {
  opt_nargs = types.union('number', 'string'),
  opt_complete = types.string,
  opt_count = types.union('number', 'string', 'boolean'),
  opt_addr = types.string,
  opt_bang = types.boolean,
  opt_bar = types.boolean,
  opt_register = types.boolean,
  opt_keepscript = types.boolean,
}

---Arguments validator
command.validator = {
  name = types.string,
  command = types.union('string', 'function'),
  opt_opts = command.opts_validator,
}

---Valid options
command.valid_opts = {
  'nargs', 'complete', 'count', 'addr', 'bang', 'bar',
  'register', 'keepscript'
}

---@type table<string,command>
---@field enabled? boolean
user_config.command = user_config.command or {}

---@param name string
---@param command string|function
---@param opts? command.opts
function command:initialize(name, cmd, opts)
  local function snake_to_camel(name)
    if not name:match '_' then
      return name
    end

    name = string.split(name, '_')
    name = list.map(name, function(word)
      return string.title(word)
    end)
    name = table.concat(name, '')

    return name
  end

  arguments.params({
    name = name, command = cmd, opt_opts = opts
  }, command.validator)

  name = snake_to_camel(name)
  self.name = name
  self.command = cmd
  self.enabled = false

  dict.merge(self, opts or {})
  user_config.command[self.name] = self
end

---@return command.opts
function command:opts()
  local res = {}
  for i = 1, #command.valid_opts do
    local k = command.valid_opts[i]
    res[k] = self[k]
  end
  return res
end

function command:enable()
  make_command(self.name, self.cmd, self:opts())
  self.enabled = true

  return self
end

function command:disable()
  if self.enabled then
    rm_command(self.name)
  end

  self.enabled = false
  return self
end

---@param name string
---@param cmd string|function
---@param opts? command.opts
function command.set(name, cmd, opts)
  local cmd = command(name, cmd, opts)
  return cmd:enable()
end

---@param name string
---@return command?
function command.rm(name)
  local cmd = user_config.command[name]
  if cmd then
    return cmd:disable() and cmd
  else
    return cmd
  end
end

---@class buffer_command : command
---@field buffer? number
---@overload fun(bufnr?: number, name: string, cmd: string|function, opts?: command.opts)
command.buffer = class 'buffer_command'

---@type table<number,command>
user_config.buffer.command = user_config.buffer.command or {}

---@param bufnr? number
---@param name string
---@param cmd string|function
---@param opts command.opts
---@return buffer_command
function command.buffer:initialize(bufnr, name, cmd, opts)
  bufnr = bufnr or vim.fn.bufnr()
  if buffer.is_invalid(bufnr) then
    errorf('buffer<%d>: Invalid buffer provided', bufnr)
  end

  self.buffer = bufnr
  self.name = name
  self.cmd = cmd

  dict.merge(self, opts or {})
  user_config.buffer.command[self.name] = self
end

command.buffer.opts = command.opts

function command.buffer:enable()
  buf_make_command(self.buffer, self.name, self.cmd, self:opts())
  self.enabled = true

  return self
end

function command.buffer:disable()
  if self.enabled then
    buf_rm_command(self.buffer, self.name)
  end

  self.enabled = false
  return self
end

---@param bufnr? number
---@param name string
---@param cmd string|function
---@param opts? command.opts
function command.buffer.set(bufnr, name, cmd, opts)
  local cmd = command.buffer(bufnr, name, cmd, opts)
  return cmd:enable()
end

---@param name string
---@return command?
function command.buffer.rm(name)
  local cmd = user_config.buffer.command[name]
  if cmd then
    return cmd:disable() and cmd
  else
    return cmd
  end
end

--- Define at bulk
command.define = bless {}
command.buffer.define = bless {}

function command.define:__index(name)
  return function(cmd, opts)
    return command.set(name, cmd, opts)
  end
end

---@param specs table<string,command>
function command.define:__call(specs)
  local res = {}
  for key, value in pairs(specs) do
    local cmd, opts = unpack(value)
    res[key] = command.set(key, cmd, opts)
  end
  return res
end

function command.buffer.define:__index(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  return function(name, cmd, opts)
    return command.buffer.set(bufnr, name, cmd, opts)
  end
end

---@param specs table<string,command>
function command.buffer.define:__call(bufnr, specs)
  local res = {}
  bufnr = bufnr or vim.fn.bufnr()

  for key, value in pairs(specs) do
    local cmd, opts = unpack(value)
    res[key] = command.buffer.set(bufnr, key, cmd, opts)
  end
  return res
end

return command
