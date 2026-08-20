#!/usr/bin/env luajit

require 'lua-utils'
require 'nvim-utils.state'

local autocmd = require 'nvim-utils.autocmd'
local validate = require 'lua-utils.validate'
local dict = require 'lua-utils.dict'

---@class keymap.opts
---@field desc? string
---@field buffer? number
---@field pattern? string|string[]
---@field event? string|string[]
---@field filetype? string|string[]
---@field once? boolean
---@field nested? boolean
---@field expr? boolean
---@field noremap? boolean
---@field replace_keycodes? boolean
---@field remap? boolean
---@field name? string|integer

---@class keymap : keymap.class : instance

---@class keymap.spec
---@field [1] string|string[]
---@field [2] string
---@field [3] string|function
---@field [4]? keymap.opts

---@class keymap.class : keymap.opts : class
---@field modes string|string[]
---@field lhs string
---@field rhs string|function
---@overload fun(modes: string|string[], lhs: string, rhs: string, opts?: keymap.opts): keymap
keymap = class 'keymap'

--- Valid keyboard options
keymap.valid_opts = { 'remap', 'buffer', 'expr', 'noremap', 'desc', 'callback', 'replace_keycodes' }

--- Valid autocmd options
keymap.valid_autocmd_opts = autocmd.valid_opts

---Keymap validator
keymap.validator = {
  mode = union('table', 'string'),
  lhs = 'string',
  rhs = union('string', 'function'),
  opt_opts = 'table',
}

---Contains all the keymap objects
user_config.keymap = user_config.keymap or {}

local function get_id(name)
  return name or (#user_config.keymap + 1)
end

local function save_id(self, name)
  local id = get_id(name)
  self.name = id
  user_config.state.keymap[id] = self
  user_config.keymap[id] = self
end

function keymap:opts()
  local res = { autocmd = {}, keymap = {}, name = self.name or get_id(self.name) }

  for _, au_key in ipairs(keymap.valid_autocmd_opts) do
    res.autocmd[au_key] = self[au_key]
  end

  for _, key in ipairs(keymap.valid_opts) do
    res.keymap[key] = self[key]
  end

  res.keymap.noremap = (res.keymap.noremap == nil and true) or res.keymap.noremap
  return res
end

---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? keymap.opts
---@return keymap
function keymap:initialize(modes, lhs, rhs, opts)
  self.modes = modes
  self.lhs = lhs
  self.rhs = rhs
  opts = opts or {}

  validate.args(
    { mode = modes, lhs = lhs, rhs = rhs, opts = opts },
    keymap.validator
  )

  dict.merge(self, opts)
  self.noremap = (self.noremap == nil and true) or self.noremap
  save_id(self, opts.name)

  ---@cast self keymap
  return self
end

---@return keymap
function keymap:enable()
  local opts = self:opts()
  local au_opts = opts.autocmd
  local kbd_opts = opts.keymap

  if self.event or self.pattern then
    local callback = function(args)
      kbd_opts = vim.deepcopy(kbd_opts)
      kbd_opts.buffer = args.buf
      vim.keymap.set(self.modes, self.lhs, self.rhs, kbd_opts)
    end
    autocmd.set(self.event, callback, au_opts)
  else
    vim.keymap.set(self.modes, self.lhs, self.rhs, kbd_opts)
  end

  ---@cast self keymap
  return self
end

---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? keymap.opts
---@return keymap
function keymap.set(modes, lhs, rhs, opts)
  local k = keymap(modes, lhs, rhs, opts)
  k:enable()
  return k
end

---@type {[string|integer]: (fun(modes: string|string[], lhs: string, rhs: string, opts?: keymap.opts): keymap)}
keymap.define = bless {}

---@param name string|integer
---@return (fun(modes: string|string[], lhs: string, rhs: string, opts?: keymap.opts): keymap)
function keymap.define:__index(name)
  return function(modes, lhs, rhs, opts)
    opts = vim.deepcopy(opts)
    opts.name = name
    return keymap.set(modes, lhs, rhs, opts)
  end
end

---@param specs {[string|integer]: keymap.spec}
---@return {[string|integer]: keymap}
function keymap.define:__call(specs)
  local res = {}
  for key, value in pairs(specs) do
    local modes, lhs, rhs, o = unpack(value)
    o = vim.deepcopy(o or {})
    o.name = o.name or key

    local kbd = keymap.set(modes, lhs, rhs, o)
    res[o.name] = kbd
  end
  return res
end

return keymap
