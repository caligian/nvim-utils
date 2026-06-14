local dict = require 'lua-utils.dict'
local list = require 'lua-utils.list'
local params = require 'lua-utils.validate'
local class = require 'lua-utils.class'
local copy = require 'lua-utils.copy'
local types = require 'lua-utils.types'
local path = require 'lua-utils.path_utils'

---@class autocmdFunctionSignature
---@field id number
---@field event string
---@field file string
---@field match string
---@field buf number
---@field data any

---@class autocmdCallbackSignature
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

---@alias autocmdEvent string|[]string
---@alias autocmdPattern string|[]string
---@alias autocmdCallback string|fun(args: autocmdCallbackSignature)

---@class autocmdOpts
---@field pattern? autocmdPattern
---@field group string|number
---@field buffer? number
---@field desc? string
---@field callback? autocmdCallback
---@field command?  autocmdCallback

---@class autocmdSpecDictSpec
---@field [1] autocmdEvent
---@field [2] autocmdCallback
---@field [3]? autocmdOpts

---@alias autocmdSpecDict table<string|autocmdSpecDictSpec>

---@class autocmdBase
---@field uid? number|boolean
---@field name? string
---@field event autocmdEvent
---@field callback? autocmdCallback
---@field command? autocmdCallback
---@field desc? string
---@field pattern? autocmdPattern|number
---@field pat? autocmdPattern|number
---@field buffer? number
---@field buf? number

---@class autocmd : autocmdBase
---@overload fun(event: autocmdEvent, callback: autocmdCallback, opts?: autocmdOpts|string|number): autocmdBase
autocmd = class 'autocmd'
autocmd.valid_opts = { "pattern", "group", "buffer", "desc", "callback", "command", 'once', 'nested' }
user_config.autocmd = user_config.autocmd or {}
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
  self.group = opts.group
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

---@param event autocmdEvent
---@param opts autocmdOpts
---@return autocmd
function autocmd.set(event, callback, opts)
  local au = autocmd(event, callback, opts)
  au:enable()
  return au
end

autocmd.define = bless {}

function autocmd.define:__index(name)
  return function (event, cb, opts)
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
