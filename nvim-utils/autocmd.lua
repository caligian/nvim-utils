require 'lua-utils'
require 'nvim-utils.state'

local validate = require 'lua-utils.validate'
local path = require 'lua-utils.path_utils'

---@class autocmd.callback.args
---@field id integer
---@field event string
---@field file string
---@field name string
---@field fullname string
---@field match string
---@field buf integer
---@field buffer integer
---@field data any
---@field dirname string
---@field basename string

---@alias autocmd.event string|string[]
---@alias autocmd.pattern string|string[]
---@alias autocmd.callback string|fun(args: autocmd.callback.args)

---@class autocmd.opts
---@field pattern? autocmd.pattern|integer
---@field group string|integer
---@field buffer? integer
---@field buf? integer
---@field desc? string
---@field callback? autocmd.callback
---@field command?  autocmd.callback
---@field once? boolean
---@field nested? boolean
---@field name? string|integer

---@class autocmd.spec
---@field [1] autocmd.event
---@field [2] autocmd.callback
---@field [3]? autocmd.opts

---@class autocmd : autocmd.class : instance

---@class autocmd.class : class
---@field id? integer
---@field name? string|integer
---@field event autocmd.event
---@field callback? autocmd.callback
---@field command? autocmd.callback
---@field desc? string
---@field pattern? autocmd.pattern|integer
---@field pat? autocmd.pattern|integer
---@field buffer? integer
---@field buf? integer
---@overload fun(event: autocmd.event, callback: autocmd.callback, opts?: autocmd.opts|string|integer): autocmd
local autocmd = class 'autocmd'

---Valid options
---@type string[]
autocmd.valid_opts = { "pattern", "group", "buffer", "desc", "callback", "command", 'once', 'nested' }

---Validator specification for initialize
autocmd.validator = {
  event = union('string', 'table'),
  run = union('callable', 'string'),
  opt_opts = 'table',
}

local state = user_config.state.autocmd
local by_name = state.by_name
local by_id = state.by_id
local opt_keys = autocmd.valid_opts

---@param name string|integer
local function get_id(name)
  return name or (#user_config.autocmd + 1)
end

---@param self autocmd
---@param name string|integer
local function save_id(self, name)
  local id = get_id(name)
  self.name = id
  by_id[id] = self
  by_name[id] = self
end

---@param ignore? string[] Ignore these keys
---@return autocmd.opts
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

---@param callback fun(args: autocmd.callback.args)|string
---@return fun(args: autocmd.callback.args)|string
local function fix_cb_params(callback)
  if type(callback) == 'string' then
    return callback
  end

  return function(args)
    ---@type autocmd.callback.args
    args = vim.deepcopy(args)
    args.buffer = args.buf
    args.filename = buffer.get_name(args.buf)
    args.basename = path.basename(args.match)
    args.dirname = path.dirname(args.match)
    callback(args)
  end
end

---@param self autocmd
---@param callback autocmd.callback
---@param opts? autocmd.opts
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

---@param self autocmd
---@param opts? autocmd.opts
local function fix_pattern(self, opts)
  opts = opts or {}
  local pattern = opts.pattern
  local buf = opts.buffer or opts.buf
  local t_pattern = type(pattern)

  if t_pattern == 'string' or t_pattern == 'table' then
    self.pattern = pattern
  elseif t_pattern == 'integer' then
    self.buffer = pattern
  elseif buf then
    fix_pattern(self, { pattern = buf })
  end
end

---@param event autocmd.event
---@param callback autocmd.callback
---@param opts? autocmd.opts
function autocmd:initialize(event, callback, opts)
  validate.autocmd(
    { event = event, run = callback, opts = opts },
    autocmd.validator
  )

  local t_opts = type(opts)
  if t_opts == 'integer' then
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
  self.id = nil
  self.name = opts.name

  fix_cb(self, callback, opts)
  fix_pattern(self, opts)
  save_id(self, opts.name)
end

---@return boolean
function autocmd:exists()
  if self.id == false then
    return false
  end

  local exists = vim.api.nvim_get_autocmds { id = self.id }
  return exists[1] ~= false or exists[1] ~= nil
end

---@param force? boolean
---@return integer
function autocmd:enable(force)
  if force then
    self.id = nil
    self:enable()
  end

  ---@type autocmd.opts
  local opts = self:opts()
  self.id = vim.api.nvim_create_autocmd(self.event, opts)
  by_id[self.id] = self

  if self.name then
    by_name[self.name] = self
  end

  return self.id
end

---@return boolean
function autocmd:disable()
  if not self.id then
    return true
  elseif self:exists() then
    vim.api.nvim_del_autocmd(self.id)
    by_id[self.id] = nil
    if self.name then by_name[self.name] = nil end
    return true
  else
    self.id = nil
    return false
  end
end

---@return integer?
function autocmd:again()
  return self:enable(true)
end

---Public facing API

---@param event autocmd.event
---@param opts autocmd.opts
---@return autocmd
function autocmd.set(event, callback, opts)
  local au = autocmd(event, callback, opts)
  autocmd.enable(au)
  return au
end

---Quickly define autocommands in bulk
---Usage:
---autocmd.define.hello('BufEnter', ':echo "hello"', {pattern = '*.lua'})
---autocmd.define { hello = {'BufEnter', 'echo "hello"', {pattern = '*.lua'}}, ... }
---@type { [string|integer]: (fun(event: autocmd.event, cb: autocmd.callback, opts?: autocmd.opts): autocmd) }
autocmd.define = bless {}

---@param name string|integer
---@return (fun(event: autocmd.event, cb: autocmd.callback, opts?: autocmd.opts): autocmd)
function autocmd.define:__index(name)
  return function(event, cb, opts)
    opts = opts or {}
    opts = vim.deepcopy(opts)
    opts.name = name
    return autocmd.set(event, cb, opts)
  end
end

---@param specs { [string|integer]: autocmd.spec }
---@return { [string|integer]: autocmd }
function autocmd.define:__call(specs)
  local res = {}
  for name, spec in pairs(specs) do
    local event, cb, opts = unpack(spec)
    opts = vim.deepcopy(opts or {})
    opts.name = tostring(opts.name or name)
    res[name] = autocmd.set(event, cb, opts)
  end
  return res
end

return autocmd
