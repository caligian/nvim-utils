#!/usr/bin/env luajit

require 'nvim-utils.autocmd'

local utils = require 'lua-utils'
local types = utils.types
local class = utils.class
local validate = utils.validate


--- Create autocommand group
---@class augroup
---@field name string
---@field autocmd table<string,autocmd> Contains all added autocommands
---@field uid? number Unique ID returned by vim
---@overload fun(name: string, clear?: boolean)
augroup = class 'augroup'

---@type table<string|number,augroup>
user_config.augroup = user_config.augroup or {}

---@type table<string,augroup>
user_config.augroup_by_uid = user_config.augroup_by_uid or {}

function augroup:initialize(name, clear)
  assert(type(name) == 'string', 'No augroup name provided')

  self.name = name
  if self:exists() and not clear then
    errorf('augroup.%s: Already exists', self.name)
  end

  self.autocmd = {}
  self.autocmd_by_uid = {}
  self.uid = vim.api.nvim_create_augroup(self.name, {clear = clear})

  user_config.augroup[self.name] = self
  user_config.augroup_by_uid[self.uid] = self
end

function augroup:exists()
  if vim.fn.exists('#' .. self.name) == 1 then
    return true
  else
    return false
  end
end

---@return boolean 
function augroup:disable()
  if not self:exists() then
    return false
  end

  for _, au in pairs(self.autocmd) do au:disable() end
  vim.api.nvim_del_augroup_by_id(self.uid)

  self.uid = false
  self.autocmd = {}
  self.autocmd_by_uid = {}

  return true
end

---@param name_or_id string|number
---@return boolean
function augroup:has(name_or_id)
  return self:get(name_or_id) ~= nil
end

---@param name_or_id string|number
---@return autocmd?
function augroup:get(name_or_id)
  return self.autocmd_by_uid[name_or_id] or self.autocmd[name_or_id] 
end

---@param name_or_id string|number
---@return autocmd?
function augroup:pop(name_or_id)
  if not name_or_id:match(self.name) then
    name_or_id = self.name .. '.' .. name_or_id
  end

  local au = self:get(name_or_id)
  if au == nil then
    return
  else
    self.augroup_by_uid[au.uid] = nil
    self.augroup[au.name] = nil
    au:disable()

    return au
  end
end

---@param event string|string[]
---@param callback string|function
---@param opts? autocmdOpts
---@return autocmd?
function augroup:append(event, callback, opts)
  if not self:exists() then
    return 
  end

  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.group = self.uid
  local name = opts.name

  if name and not name:match(self.name) then
    opts.name = self.name .. '.' .. name
  end

  opts.group = self.uid
  local au = autocmd.set(event, callback, opts)

  if au.name then
    self.autocmd[au.name] = au 
  end

  self.autocmd[au.name] = au
  self.autocmd_by_uid[au.uid] = au

  return au
end

---Other augroup utils stuff
augroup.utils = {}
local group_utils = augroup.utils

---@param name_or_id number|string
---@return augroup
function group_utils.get(name_or_id)
  return user_config.autocmd_by_uid[name_or_id] or user_config.autocmd[name_or_id]
end

---@param name_or_id number|string
---@return boolean
function group_utils.exists(name_or_id)
  return group_utils.get(name_or_id) ~= nil
end

---Create a new augroup if it does not exist
---@param name string
---@param force? boolean
---@return augroup
function group_utils.new(name, force)
  if force then
    return augroup(name)
  end

  local exists = group_utils.get(name)
  if exists:exists() then
    return exists
  else
    return augroup(name)
  end
end

---@param name string
---@param specs table<string|number,autocmd>
---@return augroup
function augroup.set(name, clear, specs)
  local group = group_utils.get(name) or augroup(name, clear)

  if specs then
    for au_name, au_spec in pairs(specs) do
      au_name = tostring(au_name)
      local event, callback, opts = unpack(au_spec)
      opts = vim.deepcopy(opts)
      opts.name = au_name
      group:append(event, callback, opts)
    end
  end

  return group
end

augroup.push = augroup.append

if not user_config.default_augroup then
  user_config.default_augroup = augroup 'user_config'
end

-- augroup.set('MyConfig', {
--   test = {'BufEnter', ':echo "world"', {pattern = "*.txt"}}
-- })

return augroup
