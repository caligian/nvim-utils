local utils = require 'lua-utils'
local types = utils.types
local class = utils.class
local validate = utils.validate
local autocmd = require 'nvim-utils.autocmd'

--- Create autocommand group
--- @class augroup
local augroup = class 'augroup'

--- Augroups
function augroup:initialize(name)
  self.name = name
  self.autocmds = {}
  self.id = vim.api.nvim_create_augroup(self.name, {clear = true})
  user_config.augroups[self.name] = self
  user_config.augroups[self.id] = self
end

function augroup:delete()
  if self.id then
    for _, au in pairs(self.autocmds) do au:delete() end
    vim.api.nvim_del_augroup_by_id(self.id)
    user_config.augroups[self.name] = nil
    user_config.augroups[self.id] = nil
    self.id = nil
    self.autocmds = {}
    return true
  end
end

augroup.del = augroup.delete

function augroup:delete_autocmd(name_or_id)
  if type(name_or_id) == 'string' then
    name_or_id = self.name .. '.' .. name_or_id
  end

  local au = self.autocmds[name_or_id]
  if au == nil then
    return
  else
    au:delete()
    self.autocmds[au.name] = nil
    return true
  end
end

augroup.del_autocmd = augroup.delete_autocmd

function augroup:add_autocmd(event, pattern, callback, opts)
  if not self.id then
    return false
  end

  opts = opts or {}
  validate.opts(opts, 'table')

  opts = vim.deepcopy(opts)
  opts.group = self.id

  if self.name and opts.name then
    opts.name = self.name .. '.' .. opts.name
  end

  opts.group = self.id
  local au = autocmd(event, pattern, callback, opts)

  if au.name then self.autocmds[au.name] = au end
  self.autocmds[#self.autocmds+1] = au

  return au
end

function augroup:add_autocmds(specs)
  for name, spec in pairs(specs) do
    validate.autocmd(spec, types.table)
    local event, pattern, callback, opts = unpack(spec)
    opts = vim.deepcopy(opts)
    opts.name = name
    self:add_autocmd(event, pattern, callback, opts)
  end
end

if not user_config.default_augroup then
  user_config.default_augroup = augroup 'user_config'
end

return augroup
