local utils = require 'lua-utils'
local dict = utils.dict
local list = utils.list
local validate = utils.validate
local types = utils.types
local class = utils.class

--- @class autocmd
local autocmd = class 'autocmd'

--- @param group integer
--- @param name string
--- @param event string | string[]
--- @param callback function 
--- @param opts table
function autocmd:initialize(event, pattern, callback, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)

  self.event = event
  self.pattern = pattern
  self.callback = nil
  self.command = nil
  self.name = opts.name
  self.desc = opts.desc
  self.buffer = opts.buffer
  self.group = opts.buffer
  self.once = opts.once
  self.nested = opts.nested

  dict.merge(self, opts or {})

  if types.string(callback) then
    self.command = callback
  else
    validate.callback(callback, types.callable)
    self.callback = callback
  end

  if not self.desc then
    self.desc = self.name
  end

  self:enable()
end

function autocmd:args()
  return {
    self.event, {
      pattern = self.pattern,
      callback = self.callback,
      command = self.command,
      group = self.group,
      once = self.once,
      nested = self.nested,
      buffer = self.buffer,
      desc = self.desc,
    }
  }
end

function autocmd:enable()
  if not self.id then
      local args = self:args()
    self.id = apply(vim.api.nvim_create_autocmd, self:args())
    user_config.autocmds[self.id] = self
    if self.name then user_config.autocmds[self.name] = self end
    return self.id
  else
    return self.id
  end
end

function autocmd:delete()
  if self.id then
    vim.api.nvim_del_autocmd(self.id)
    user_config.autocmds[self.id] = nil
    if self.name then user_config.autocmds[self.name] = nil end
    return true
  end
end

function autocmd:restart()
  self:delete()
  return self:enable()
end

autocmd.del = autocmd.delete

return autocmd
