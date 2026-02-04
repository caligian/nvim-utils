local utils = require 'lua-utils'
local types = utils.types
local list = utils.list
local dict = utils.dict
local class = utils.class
local nvim = require('nvim-utils.nvim')
local buffer = require('nvim-utils.buffer')
local augroup = require('nvim-utils.augroup')
local picker = require('nvim-utils.picker')

--- @diagnostic disable: missing-fields

--- Buffer groups
--- Somewhat like project management buffers
local buffer_group = class 'buffer_group'
user_config.buffer_group = buffer_group

function buffer_group:initialize(name, pattern, event)
  self.event = event or 'BufRead'
  self.name = name
  self.group = augroup('buffer_group.' .. name)
  self.pattern = pattern or '*.*'
  self.buffers = {}
  self.removed = {}
  self.cache = {buffers = {}, removed = {}}
  user_config.buffer_groups[name] = self
end

function buffer_group:clean()
  for i=1, #self.buffers do
    local exists = self.buffers[i]
    if not buffer.exists(exists[1]) then
      self:delete(exists[1])
    end
  end

  for i=1, #self.removed do
    local exists = self.buffers[i]
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
    return self.buffers
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
  if self.cache.buffers[bufnr] then
    return true
  end

  local bufname = buffer.name(bufnr)
  if self.cache.buffers[bufname] then
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
    for i=1, #self.pattern do
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

  local len = #self.buffers + 1
  self.buffers[len] = {bufnr, bufname}
  self.cache.buffers[bufnr] = self.buffers[len]
  self.cache.buffers[bufname] = self.buffers[len]
  dict.set(user_config.buffers, {bufname, 'buffer_groups', self.name}, self, true)
  dict.set(user_config.buffers, {bufnr, 'buffer_groups', self.name}, self, true)
  vim.api.nvim_create_autocmd({'BufWipeout', 'BufDelete'}, {
    buffer = bufnr,
    callback = function (args)
      self:remove(args.buf)
    end
  })
  return true
end

function buffer_group:has(bufnr, removed)
  local xs = ifnil(removed, self.cache.buffers, self.cache.removed)
  return xs[bufnr] ~= nil
end

function buffer_group:index(bufnr, removed)
  if not buffer.exists(bufnr) then
    return false
  end

  local search_in = ifelse(removed, self.removed, self.buffers)
  local is_num = types.number(bufnr)
  local is_str = types.string(bufnr)

  for i=1, #search_in do
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
    local x = self.buffers[ind]
    self.removed[#self.removed+1] = x
    self.cache.removed[x[1]] = x
    self.cache.removed[x[2]] = x
    self.cache.buffers[x[1]] = false
    self.cache.buffers[x[2]] = false
    dict.set(user_config.buffers, {x[1], 'buffer_groups', self.name}, false, true)
    dict.set(user_config.buffers, {x[2], 'buffer_groups', self.name}, false, true)
    table.remove(self.buffers, ind)
    return true
  end
end

function buffer_group:delete(bufnr, force)
  local ind = self:index(bufnr)
  if ind then
    local exists = self.buffers[ind]
    table.remove(self.buffers, ind)
    self.cache.buffers[exists[1]] = nil
    self.cache.buffers[exists[2]] = nil
    pcall(buffer.delete, exists[1], force)

    dict.set(user_config.buffers, {exists[1], 'buffer_groups', self.name}, false, true)
    dict.set(user_config.buffers, {exists[2], 'buffer_groups', self.name}, false, true)
  end

  ind = self:index(bufnr, true)
  if not ind then
    return
  end

  local exists = self.removed[ind]
  table.remove(self.removed, ind)
  self.cache.removed[exists[1]] = nil
  self.cache.removed[exists[2]] = nil
  pcall(buffer.delete, exists[1])

  dict.set(user_config.buffers, {exists[1], 'buffer_groups'}, false, true)
  dict.set(user_config.buffers, {exists[2], 'buffer_groups'}, false, true)
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
    self.buffers[#self.buffers+1] = x
    self.cache.removed[x[1]] = false
    self.cache.removed[x[2]] = false
    self.cache.buffers[x[1]] = x
    self.cache.buffers[x[2]] = x
    dict.set(user_config.buffers, {x[1], 'buffer_groups', self.name}, self, true)
    dict.set(user_config.buffers, {x[2], 'buffer_groups', self.name}, self, true)
    return true
  end
end

function buffer_group:picker(restore)
  local name = self.name:gsub(os.getenv('HOME'), '~')
  local title = sprintf('Buffer group (%s)', name)
  title = ifelse(restore, sprintf('Buffer group [restore] (%s)', name), title)
  local p = picker(title)
  local mod = p.actions

  function mod.delete(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function (entry)
      self:delete(entry.value)
    end)
  end

  function mod.wipeout(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function (entry)
      self:wipeout(entry.value)
    end)
  end

  function mod.remove(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function (entry)
      self:remove(entry.value)
    end)
  end

  function mod.restore(prompt_bufnr)
    list.each(p:entries(prompt_bufnr), function (entry)
      self:restore(entry.value)
    end)
  end

  function mod.open(prompt_bufnr)
    local bufnr = p:entry(prompt_bufnr).value
    local valid = buffer.exists(bufnr)

    if valid and not buffer.visible(bufnr) then
      vim.cmd(paste0('buffer! ', bufnr))
    elseif not valid then
      self:delete(bufnr)
    end
  end

  local choices
  if restore then
    choices = self.removed
  else
    choices = self.buffers
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
    default_action = function (selection)
      self:restore(selection.value)
    end
  else
    default_action = function (selection)
      local bufnr = selection.value
      local valid = buffer.exists(bufnr)

      if valid and not buffer.visible(bufnr) then
        vim.cmd(paste0('buffer! ', bufnr))
      elseif not valid then
        self:delete(bufnr)
      end
    end
  end

  local mappings = {
    {'n', 'o', 'open', 'Open buffer'},
    {'n', 'd', 'delete', 'Delete buffer'},
    {'n', 'x', 'wipeout', 'Wipeout buffer'},
    {'n', 'r', 'remove', 'Blacklist buffer'},
  }

  if restore then
    mappings[#mappings+1] = {'n', '<CR>', 'restore', 'Restore buffer'}
    mappings[#mappings+1] = {'i', '<CR>', 'restore', 'Restore buffer'}
    mappings[#mappings+1] = {'n', 'p', 'restore', 'Restore buffer'}
  else
    mappings[#mappings+1] = {'n', '<CR>', 'open', 'Open buffer'}
    mappings[#mappings+1] = {'i', '<CR>', 'open', 'Open buffer'}
  end

  return p:find(choices, default_action, {
    keymaps = mappings,
    entry_maker = entry_maker
  })
end

function buffer_group.buffer_group_picker(groups)
  groups = groups or dict.values(user_config.buffer_groups)
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
    {'n', '<CR>', 'open', 'Open picker'},
    {'i', '<CR>', 'open', 'Open picker'},
    {'n', 'r', 'restore', 'Open restore picker'},
    {'i', '<C-r>', 'restore', 'Open restore picker'},
    {'i', '<C-m>', 'restore', 'Open restore picker'},
  }

  return p:find(choices, default_action, {
    keymaps = mappings,
    entry_maker = entry_maker
  })
end

--- restore option only valid when there is only one buffer group
--- for that buffer
function buffer_group.buffer_picker(bufnr, restore)
  bufnr = bufnr or buffer.current()

  if not buffer.exists(bufnr) then
    return false
  end

  local bufname = buffer.name(bufnr)
  local groups = dict.get(user_config.buffers, {bufnr, 'buffer_groups'})
  groups = groups or dict.get(user_config.buffers, {bufname, 'buffer_groups'})

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

  return buffer_group.buffer_group_picker(dict.values(groups))
end

function buffer_group.from(specs)
  for name, pattern in pairs(specs) do
    buffer_group(name, pattern)
  end
  return true
end

function buffer_group.load_config()
  return nvim.require('config.buffer_groups', function(groups)
    return buffer_group.from(groups)
  end)
end

function buffer_group.setup()
  buffer_group.load_config()
  vim.api.nvim_create_autocmd('BufRead', {
    pattern = '*.*',
    callback = function(args)
      for _, group in pairs(user_config.buffer_groups) do
        group:add(args.buf)
      end
    end
  })
end

return buffer_group
