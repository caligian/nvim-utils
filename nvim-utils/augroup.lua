require 'lua-utils'

local autocmd = require 'nvim-utils.autocmd'
local mkgroup = vim.api.nvim_create_augroup

---@class augroup.autocmd
---@field by_id table<integer,autocmd>
---@field by_name table<string|integer,autocmd>

---@class augroup : augroup.class : instance

---Create autocommand group
---@class augroup.class : class
---@field name string
---@field autocmd augroup.autocmd
---@field id? integer Unique ID returned by vim
---@overload fun(name: string, clear?: boolean): augroup
local augroup = class 'augroup'
local state = user_config.state.augroup
local by_id = state.by_id
local by_name = state.by_name

function augroup:initialize(name, clear)
  ---@cast self augroup
  self = self
  assert(type(name) == 'string', 'No augroup name provided')

  self.name = name
  if self:exists() and not clear then
    errorf('augroup.%s: Already exists', self.name)
  end

  self.autocmd = { by_id = {}, by_name = {} }
  self.id = mkgroup(self.name, { clear = clear })

  by_id[self.id] = self
  by_name[self.name] = self
end

---Check if augroup exists
---@return boolean
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
  vim.api.nvim_del_augroup_by_id(self.id)
  self.id = nil
  self.autocmd = { by_id = {}, by_name = {} }

  return true
end

---@param name_or_id string|integer
---@return boolean
function augroup:has(name_or_id)
  return self:get(name_or_id) ~= nil
end

---@param name_or_id string|integer
---@return autocmd?
function augroup:get(name_or_id)
  return self.autocmd.by_id[name_or_id] or self.autocmd.by_name[name_or_id]
end

---@param name_or_id string|integer
---@return autocmd?
function augroup:pop(name_or_id)
  if not name_or_id:match(self.name) then
    name_or_id = self.name .. '.' .. name_or_id
  end

  local au = self:get(name_or_id)
  if au == nil then
    return
  else
    self.autocmd.by_id[au.id] = nil
    self.autocmd.by_name[au.name] = nil
    au:disable()
    return au
  end
end

---@param event string|string[]
---@param callback string|function
---@param opts? autocmd.opts
---@return autocmd?
function augroup:append(event, callback, opts)
  if not self:exists() then
    return
  end

  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.group = self.id
  local name = opts.name

  if name and not name:match(self.name) then
    opts.name = self.name .. '.' .. name
  end

  opts.group = self.id
  local au = autocmd.set(event, callback, opts)

  if au.name then
    self.autocmd.by_name[au.name] = au
  end

  self.autocmd.by_id[au.id] = au
  return au
end

---Command augroup utilities
augroup.utils = {}
local group_utils = augroup.utils

---@param name_or_id integer|string
---@return augroup
function group_utils.get(name_or_id)
  return by_id[name_or_id] or by_name[name_or_id]
end

---@param name_or_id integer|string
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
---@param clear boolean
---@param specs table<string|integer,autocmd>
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
  user_config.default_augroup = augroup('user_config', true)
end

-- augroup.set('MyConfig', false, {
--   test = {'BufEnter', ':echo "world"', {pattern = "*.txt"}}
-- })

return augroup
