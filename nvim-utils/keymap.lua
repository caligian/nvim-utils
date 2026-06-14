local lutils = require 'lua-utils'
local types = lutils.types
local validate = lutils.validate
local class = lutils.class
local dict = lutils.dict

local utils = require 'nvim-utils.utils'
require 'nvim-utils.autocmd'

---@class keymapOpts
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

---@class keymap : keymapOpts
---@field modes string|string[]
---@field lhs string
---@field rhs string
---@overload fun(modes: string|string[], lhs: string, rhs: string, opts?: keymapOpts)
keymap = class 'keymap'
keymap.valid_opts = {'remap', 'buffer', 'expr', 'noremap', 'desc', 'callback', 'replace_keycodes'}
keymap.valid_autocmd_opts = autocmd.valid_opts

---Contains all the keymap objects
user_config.keymap = user_config.keymap or {}

local function get_id(name)
  return name or (#user_config.keymap + 1)
end

local function save_id(self, name)
  local id = get_id(name)
  self.name = id
  user_config.keymap[id] = self
end

function keymap:opts()
  local res = {autocmd = {}, keymap = {}, name = self.name or get_id(self.name)}

  for _, au_key in ipairs(keymap.valid_autocmd_opts) do
    res.autocmd[au_key] = self[au_key]
  end

  for _, key in ipairs(keymap.valid_opts) do
    res.keymap[key] = self[key]
  end

  return res
end


---@param modes string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? keymapOpts
---@return keymap
function keymap:initialize(modes, lhs, rhs, opts)
  self.modes = modes
  self.lhs = lhs
  self.rhs = rhs

  opts = opts or {}
  dict.merge(self, opts)
  save_id(self, opts.name)

  return self
end

function keymap:enable()
  local opts = self:opts()
  local au_opts = opts.autocmd
  local kbd_opts = opts.keymap
  local name = opts.name

  if self.event or self.pattern then
    local callback = function (args)
      kbd_opts = vim.deepcopy(kbd_opts)
      kbd_opts.buffer = args.buf
      vim.keymap.set(self.modes, self.lhs, self.rhs, kbd_opts)
    end
    autocmd.set(self.event, callback, au_opts)
  else
    vim.keymap.set(self.modes, self.lhs, self.rhs, kbd_opts)
  end
end

function keymap.set(modes, lhs, rhs, opts)
  keymap(modes, lhs, rhs, opts):enable()
  return self
end

keymap.define = bless {}
function keymap.define:__index(name)
  return function (modes, lhs, rhs, opts)
    keymap.set(modes, lhs, rhs, opts)
  end
end

function keymap.define:__call(specs)
  local res = {}
  for key, value in pairs(specs) do
    local modes, lhs, rhs, o = unpack(value)
    o = dict.merge(vim.deepcopy(o or {}), opts) 
    o.name = o.name or key
    local kbd = keymap.set(modes, lhs, rhs, o)
    res[o.name] = kbd
  end
  return res
end

return keymap
