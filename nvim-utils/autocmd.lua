#!/usr/bin/env luajit

require 'nvim-utils.state'

local lutils = require 'lua-utils'
local class = require 'lua-utils.class'
local types = require 'lua-utils.types'
local path = require 'lua-utils.path_utils'
local validate = lutils.validate

---@class autocmd.callback.args
---@field id number
---@field event string
---@field file string
---@field name string
---@field fullname string
---@field match string
---@field buf number
---@field buffer number
---@field data any
---@field dirname string
---@field basename string

---@alias autocmd.event string|string[]
---@alias autocmd.pattern string|string[]
---@alias autocmd.callback string|fun(args: autocmd.callback.args)

---@class autocmd.opts
---@field pattern? autocmd.pattern
---@field group string|number
---@field buffer? number
---@field desc? string
---@field callback? autocmd.callback
---@field command?  autocmd.callback

---@class autocmd.config.shape
---@field [1] autocmd.event
---@field [2] autocmd.callback
---@field [3]? autocmd.opts

---@class autocmd.shape
---@field uid? number|boolean
---@field name? string
---@field event autocmd.event
---@field callback? autocmd.callback
---@field command? autocmd.callback
---@field desc? string
---@field pattern? autocmd.pattern|number
---@field pat? autocmd.pattern|number
---@field buffer? number
---@field buf? number

---@class autocmd : autocmd.shape
---@overload fun(event: autocmd.event, callback: autocmd.callback, opts?: autocmd.opts|string|number): autocmd.shape
autocmd = class 'autocmd'

---Valid options
---@type string[]
autocmd.valid_opts = { "pattern", "group", "buffer", "desc", "callback", "command", 'once', 'nested' }

autocmd.validator = {
  event = types.union('string', 'table'),
  run = types.union('callable', 'string'),
  opt_opts = 'table',
}

---Global state
---@type table<string|number,autocmd>
user_config.autocmd = user_config.autocmd or {}

---@class autocmd.config.shape
---@field [1] autocmd.event
---@field [2] autocmd.callback
---@field [3]? autocmd.opts

---@type table<number,autocmd>
user_config.autocmd_by_uid = user_config.autocmd_by_uid or {}

local t_str_or_fun = types.union('string', 'function')
local t_str_or_num = types.union('string', 'number')
local opt_keys = autocmd.valid_opts

local function get_id(name)
  return name or (#user_config.autocmd + 1)
end

local function save_id(self, name)
  local id = get_id(name)
  self.name = id
  user_config.autocmd[id] = self
end

function autocmd:opts(ignore)
  local res = {}

  for _, key in ipairs(opt_keys) do
    if ignore then
      for _, ig in ipairs(ignore) do
        if key ~= ig then
          res[key] = self[key]
        end
      end
    else
      res[key] = self[key]
    end
  end

  return res
end

local function fix_cb_params(callback)
  if type(callback) == 'string' then
    return callback
  end

  return function(args)
    args = vim.deepcopy(args)
    args.buffer = args.buf
    args.filename = vim.api.nvim_buf_get_name(args.buf)
    args.basename = path.basename(args.match)
    args.dirname = dirname(args.match)

    callback(args)
  end
end

local function fix_cb(self, callback, opts)
  opts = opts or {}
  if callback ~= nil then
    if callable(callback) then
      self.callback = fix_cb_params(callback)
    elseif type(callback) == 'string' then
      self.command = fix_cb_params(callback)
    else
      error('callback: Expected string|callable, got ' .. dump(callback))
    end
  elseif opts == nil then
    return
  elseif opts.callback ~= nil then
    fix_cb(self, opts.callback)
  elseif opts.command ~= nil then
    fix_cb(self, opts.command)
  end
end

local function fix_pattern(self, opts)
  opts = opts or {}
  local pattern = opts.pattern
  local buf = opts.buffer or opts.buf
  local t_pattern = type(pattern)

  if t_pattern == 'string' or t_pattern == 'table' then
    self.pattern = pattern
  elseif t_pattern == 'number' then
    self.buffer = pattern
  elseif buf then
    fix_pattern(self, { pattern = buf })
  end
end

function autocmd:initialize(event, callback, opts)
  validate.autocmd(
    { event = event, run = callback, opts = opts },
    autocmd.validator
  )

  local t_opts = type(opts)
  if t_opts == 'number' then
    self.buffer = opts
    opts = {}
  elseif t_opts == 'string' then
    self.desc = opts
    opts = {}
  end

  opts = opts or {}
  self.event = event
  self.desc = self.desc or opts.desc
  self.group = opts.group or 'user_config'
  self.once = opts.once
  self.nested = opts.nested
  self.uid = false

  fix_cb(self, callback, opts)
  fix_pattern(self, opts)
  save_id(self, opts.name)
end

---@return boolean
function autocmd:exists()
  if self.uid == false then
    return false
  end

  local exists = vim.api.nvim_get_autocmds { id = self.uid }
  return exists[1] ~= false or exists[1] ~= nil
end

---@param force? boolean
---@return number
function autocmd:enable(force)
  if force then
    self.uid = false
    self:enable()
  end

  self.uid = vim.api.nvim_create_autocmd(self.event, self:opts())
  user_config.autocmd_by_uid[self.uid] = self
  return self.uid
end

---@return boolean
function autocmd:disable()
  if self.uid == false then
    return true
  elseif self:exists() then
    vim.api.nvim_del_autocmd(self.uid)
    user_config.autocmd_by_uid[self.uid] = nil
    user_config.autocmd[self.name] = nil
    return true
  else
    self.uid = false
    return false
  end
end

---@return boolean
function autocmd:again()
  return self:enable(true)
end

---Public facing API

---@param event autocmd.event
---@param opts autocmd.opts
---@return autocmd
function autocmd.set(event, callback, opts)
  local au = autocmd(event, callback, opts)
  au:enable()

  return au
end

---Quickly define autocommands in bulk
---Usage:
---autocmd.define.hello('BufEnter', ':echo "hello"', {pattern = '*.lua'})
---autocmd.define { hello = {'BufEnter', 'echo "hello"', {pattern = '*.lua'}}, ... }
---@overload fun(specs: table<string, autocmd.config.shape>): table<string,autocmd.config.shape>
autocmd.define = bless {}

function autocmd.define:__index(name)
  return function(event, cb, opts)
    opts = opts or {}
    opts = vim.deepcopy(opts)
    opts.name = name
    return autocmd.set(event, cb, opts)
  end
end

function autocmd.define:__call(specs)
  local res = {}
  for name, spec in pairs(specs) do
    local event, cb, opts = unpack(spec)
    opts = vim.deepcopy(opts or {})
    opts.name = opts.name or name
    res[name] = autocmd.set(event, cb, opts)
  end
  return res
end

return autocmd
