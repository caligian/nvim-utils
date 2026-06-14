require 'nvim-utils.state'
require('nvim-utils.buffer')
require('nvim-utils.augroup')

local utils = require 'lua-utils'
local types = utils.types
local list = utils.list
local dict = utils.dict
local class = utils.class
local nvim = require('nvim-utils.nvim')
local picker = require('nvim-utils.picker')

---@class buffer_group.cache
---@field buffer table<number,string>
---@field removed table<number,string>

--- Buffer groups
---@class buffer_group
---@field event string|[]string
---@field name string
---@field group number
---@field pattern string|string[]|function
---@field buffer table<number,boolean>
---@field removed table<number,boolean>
---@field cache buffer_group.cache
---@overload fun(name: string, pattern?: string|string[]|function, event?: string|string[])
buffer_group = class 'buffer_group'
buffer_group.utils = {}
user_config.buffer_group = user_config.buffer_group or {}

function buffer_group:initialize(name, pattern, event)
  self.event = event or 'BufRead'
  self.name = name
  self.group = augroup.set('user_config.buffer_group.' .. name, true)
  self.pattern = pattern or '*.*'
  self.buffer = {}
  self.removed = {}
  self.cache = { buffer = {}, removed = {} }

  user_config.buffer_group[name] = self
end

function buffer_group:clean()
  for i = 1, #self.buffer do
    local exists = self.buffer[i]
    if not buffer.exists(exists[1]) then
      self:delete(exists[1])
    end
  end

  for i = 1, #self.removed do
    local exists = self.buffer[i]
    if not buffer.exists(exists[1]) then
      self:delete(exists[1])
    end
  end
end

function buffer_group:list(removed)
  self:clean()

  if removed then
    return self.removed
  else
    return self.buffer
  end
end

function buffer_group:disable()
  if self.enabled then
    self.enabled = false
    self.group:delete()
    self.group = false
  end
end

function buffer_group:add(bufnr)
  if self.cache.buffer[bufnr] then
    return true
  end

  local bufname = buffer.get_name(bufnr)
  if self.cache.buffer[bufname] then
    return true
  elseif not buffer.exists(bufnr) then
    return false
  elseif self.cache.removed[bufnr] or self.cache.removed[bufname] then
    return false
  elseif not types.string(self.pattern) and not types.callable(self.pattern) then
    return false
  elseif types.string(self.pattern) then
    if not bufname:find(self.pattern, 1, true) then
      return false
    end
  elseif types.table(self.pattern) then
    for i = 1, #self.pattern do
      local pattern = self.pattern[i]
      if not bufname:find(pattern, 1, true) then
        return false
      end
    end
  elseif types.callable(self.pattern) then
    if not self.pattern(bufnr) then
      return false
    end
  end

  local len = #self.buffer + 1
  self.buffer[len] = { bufnr, bufname }
  self.cache.buffer[bufnr] = self.buffer[len]
  self.cache.buffer[bufname] = self.buffer[len]
  dict.set(user_config.buffer, { bufname, 'buffer_group', self.name }, self, true)
  dict.set(user_config.buffer, { bufnr, 'buffer_group', self.name }, self, true)
  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
    buffer = bufnr,
    callback = function(args)
      self:remove(args.buf)
    end
  })
  return true
end

function buffer_group:has(bufnr, removed)
  local xs = when_nil(removed, L(self.cache.buffer), L(self.cache.removed))
  return xs[bufnr] ~= nil
end

function buffer_group:index(bufnr, removed)
  if not buffer.exists(bufnr) then
    return false
  end

  local search_in = removed and self.removed or self.buffer
  local is_num = types.number(bufnr)
  local is_str = types.string(bufnr)

  for i = 1, #search_in do
    local buf, bufname = unpack(search_in[i])
    if is_num and bufnr == buf then
      return i
    elseif is_str and bufnr == bufname then
      return i
    end
  end

  return false
end

function buffer_group:remove(bufnr)
  local ind = self:index(bufnr)
  if not ind then
    return false
  else
    local x = self.buffer[ind]
    self.removed[#self.removed + 1] = x
    self.cache.removed[x[1]] = x
    self.cache.removed[x[2]] = x
    self.cache.buffer[x[1]] = false
    self.cache.buffer[x[2]] = false
    dict.set(user_config.buffer, { x[1], 'buffer_group', self.name }, false, true)
    dict.set(user_config.buffer, { x[2], 'buffer_group', self.name }, false, true)
    table.remove(self.buffer, ind)
    return true
  end
end

function buffer_group:delete(bufnr, force)
  local ind = self:index(bufnr)
  if ind then
    local exists = self.buffer[ind]
    table.remove(self.buffer, ind)
    self.cache.buffer[exists[1]] = nil
    self.cache.buffer[exists[2]] = nil
    pcall(buffer.delete, exists[1], force)

    dict.set(user_config.buffer, { exists[1], 'buffer_group', self.name }, false, true)
    dict.set(user_config.buffer, { exists[2], 'buffer_group', self.name }, false, true)
  end

  ind = self:index(bufnr, true)
  if not ind then
    return
  end

  local exists = self.removed[ind]
  table.remove(self.removed, ind)
  self.cache.removed[exists[1]] = nil
  self.cache.removed[exists[2]] = nil
  pcall(buffer.rm, exists[1])

  dict.set(user_config.buffer, { exists[1], 'buffer_group' }, false, true)
  dict.set(user_config.buffer, { exists[2], 'buffer_group' }, false, true)
end

function buffer_group:wipeout(bufnr)
  self:delete(bufnr, true)
end

function buffer_group:restore(bufnr)
  local x = self.cache.removed[bufnr]
  if not x then
    return false
  else
    local ind = self:index(bufnr, true)
    table.remove(self.removed, ind)
    self.buffer[#self.buffer + 1] = x
    self.cache.removed[x[1]] = false
    self.cache.removed[x[2]] = false
    self.cache.buffer[x[1]] = x
    self.cache.buffer[x[2]] = x
    dict.set(user_config.buffer, { x[1], 'buffer_group', self.name }, self, true)
    dict.set(user_config.buffer, { x[2], 'buffer_group', self.name }, self, true)
    return true
  end
end

function buffer_group:picker(restore)
  local name = self.name:gsub(os.getenv('HOME'), '~')
  local title = sprintf('Buffer group (%s)', name)
  title = restore and sprintf('Buffer group [restore] (%s)', name) or title
  local p = picker(title)
  local mod = p.actions

  function mod.delete(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function(entry)
      self:delete(entry.value)
    end)
  end

  function mod.wipeout(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function(entry)
      self:wipeout(entry.value)
    end)
  end

  function mod.remove(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function(entry)
      self:remove(entry.value)
    end)
  end

  function mod.restore(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function(entry)
      self:restore(entry.value)
    end)
  end

  function mod.open(prompt_bufnr)
    local bufnr = p:entry(prompt_bufnr).value
    local valid = buffer.exists(bufnr)

    if valid and not buffer.is_visible(bufnr) then
      vim.cmd(paste0('buffer! ', bufnr))
    elseif not valid then
      self:delete(bufnr)
    end
  end

  local choices
  if restore then
    choices = self.removed
  else
    choices = self.buffer
  end

  if #choices == 0 then
    return
  end

  local home = os.getenv('HOME')
  local function entry_maker(entry)
    return {
      display = entry[2]:gsub(home, '~'),
      value = entry[1],
      ordinal = entry[2],
    }
  end

  local default_action
  if restore then
    default_action = function(selection)
      self:restore(selection.value)
    end
  else
    default_action = function(selection)
      local bufnr = selection.value
      local valid = buffer.exists(bufnr)

      if valid and not buffer.is_visible(bufnr) then
        vim.cmd(paste0('buffer! ', bufnr))
      elseif not valid then
        self:delete(bufnr)
      end
    end
  end

  local mappings = {
    { 'n', 'o', 'open',    'Open buffer' },
    { 'n', 'd', 'delete',  'Delete buffer' },
    { 'n', 'x', 'wipeout', 'Wipeout buffer' },
    { 'n', 'r', 'remove',  'Blacklist buffer' },
  }

  if restore then
    mappings[#mappings + 1] = { 'n', '<CR>', 'restore', 'Restore buffer' }
    mappings[#mappings + 1] = { 'i', '<CR>', 'restore', 'Restore buffer' }
    mappings[#mappings + 1] = { 'n', 'p', 'restore', 'Restore buffer' }
  else
    mappings[#mappings + 1] = { 'n', '<CR>', 'open', 'Open buffer' }
    mappings[#mappings + 1] = { 'i', '<CR>', 'open', 'Open buffer' }
  end

  return p:find(choices, default_action, {
    keymaps = mappings,
    entry_maker = entry_maker
  })
end

---
local utils = buffer_group.utils

function utils.buffer_group_picker(groups)
  groups = groups or dict.values(user_config.buffer_group)
  if #groups == 0 then
    return
  end

  local p = picker('Select buffer group')
  local choices = groups
  local function entry_maker(entry)
    local name = entry.name:gsub(os.getenv('HOME'), '~')
    local display

    if types.callable(entry.pattern) then
      display = name
    elseif types.string(entry.pattern) then
      display = sprintf('%s :: %s', name, entry.pattern)
    else
      display = name
    end

    return {
      display = display,
      ordinal = entry.name,
      value = entry
    }
  end
  local function default_action(selection)
    selection.value:picker()
  end
  local actions = p.actions

  function actions.open(prompt_bufnr)
    local entry = p:entry(prompt_bufnr)
    if #entry.value.buffers == 0 then
      printf('No entries have been added in %s', entry.value.name)
    else
      entry.value:picker()
    end
  end

  function actions.restore(prompt_bufnr)
    local entry = p:entry(prompt_bufnr)
    if #entry.value.removed == 0 then
      printf('No entries have been removed from %s', entry.value.name)
    else
      entry.value:picker(true)
    end
  end

  local mappings = {
    { 'n', '<CR>',  'open',    'Open picker' },
    { 'i', '<CR>',  'open',    'Open picker' },
    { 'n', 'r',     'restore', 'Open restore picker' },
    { 'i', '<C-r>', 'restore', 'Open restore picker' },
    { 'i', '<C-m>', 'restore', 'Open restore picker' },
  }

  return p:find(choices, default_action, {
    keymaps = mappings,
    entry_maker = entry_maker
  })
end

--- restore option only valid when there is only one buffer group
--- for that buffer
---@return boolean, string?
function utils.buffer_picker(bufnr, restore)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local bufname = buffer.get_name(buf)
      local groups = dict.get(user_config.buffer, { buf, 'buffer_group' })
      groups = groups or dict.get(user_config.buffer, { bufname, 'buffer_group' })

      if not groups then
        printf('No buffer groups added for %s', bufname)
        return false
      elseif #groups == 1 then
        if restore then
          groups[1]:picker(true)
        else
          groups[1]:picker(false)
        end
      end

      return utils.buffer_group_picker(dict.values(groups))
    end,
    err = function(msg)
      return false, msg
    end
  })
end

---@return table<string,buffer_group>
function utils.load_table(specs)
  local res = {}
  for name, pattern in pairs(specs) do
    res[name] = buffer_group(name, pattern)
  end
  return res
end

---@return boolean, table<string,buffer_group>|string?
function utils.load_config(overrides)
  local ok, msg = pcall(require, 'config.buffer_group')
  local config

  if not ok then
    return false, msg
  elseif type(msg) ~= 'table' then
    return false, 'buffer_group: Expected table'
  else
    config = msg
  end

  overrides = dict.merge(vim.deepcopy(overrides or {}), config)
  return utils.load_table(overrides)
end

function utils.setup(overrides)
  utils.load_config(overrides)

  local res = {}
  for name, path in pairs(user_config.path.project or {}) do
    res[name] = buffer_group(name, path, 'BufRead')
  end

  local group = augroup.set('user_config.buffer_group', true)
  group:append(
    'BufRead',
    function(args)
      local buf = args.buf
      local ok, _ = buffer.get_filetype(buf)

      if not ok then
        return
      end

      for _, group in pairs(user_config.buffer_group) do
        group:add(args.buf)
      end

      local ws = buffer.get_root_dir(buf) or dirname(buf)
      local exists = user_config.buffer_group[ws]

      if not exists then
        exists = buffer_group(ws, ws)
      end

      exists:add(buf)
    end,
    { pattern = '*.*', desc = 'Add buffer to buffer-groups' }
  )

  return res
end

buffer_group.push = buffer_group.add
buffer_group.append = buffer_group.add

return buffer_group
