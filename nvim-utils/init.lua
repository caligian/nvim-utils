user_config = {}
user_config.keymaps = {}
user_config.buffers = {buffer_groups = {}, recent = {}}
user_config.buffer_groups = {}
user_config.filetypes = user_config.filetypes or {}
user_config.terminals = user_config.terminals or {}
user_config.repls = user_config.repls or { repls = {}, shells = {}, shell = false }
user_config.augroups = user_config.augroups or {}
user_config.autocmds = user_config.autocmds or {}
user_config.dir = vim.fn.stdpath('config')
user_config.lua_dir = vim.fn.stdpath('config') .. '/lua'
user_config.config_dir = user_config.lua_dir .. '/config'
user_config.filetypes_dir = user_config.config_dir .. '/filetypes'
user_config.data_dir = vim.fn.stdpath('data')
user_config.workspaces = user_config.workspaces or {}
user_config.shell_command = user_config.shell_command or 'bash'
user_config.telescope = {
  theme = 'ivy',
  disable_devicons = true,
  previewer = false,
  layout_config = {height = 13}
}

local lua_utils = require 'lua-utils'
for k, v in pairs(lua_utils) do
  user_config[k] = v
end

lua_utils:import()

local augroup = require('nvim-utils.augroup')
local window = require('nvim-utils.window')
local buffer = require('nvim-utils.buffer')
local tabpage = require('nvim-utils.tabpage')
local filetype  = require('nvim-utils.filetype')
local repl = require('nvim-utils.repl')
local nvim = require('nvim-utils.nvim')
local terminal = require('nvim-utils.terminal')
local buffer_group = require('nvim-utils.buffer_group')
local picker = require('nvim-utils.picker')
local autocmd = require 'nvim-utils.autocmd'
local keymap = require 'nvim-utils.keymap'
local path = require 'lua-utils.path_utils'

---Get dirname of buffer/path
---@param buf number|string? (default: 0)
function dirname(buf)
  buf = buf or buffer.current()
  if types.number(buf) then
    buf = buffer.name(buf)
    return path.dirname(buf)
  elseif types.string(buf) then
    return path.dirname(buf)
  end
end

--- Nvim lib
user_config.path = path
user_config.keymap = keymap
user_config.buffer_group = buffer_group
user_config.terminal = terminal
user_config.augroup = augroup
user_config.window = window
user_config.buffer = buffer
user_config.filetype = filetype
user_config.repl = repl
user_config.tabpage = tabpage
user_config.nvim = nvim
user_config.picker = picker

function user_config:path(...)
  local args = {...}
  table.insert(args, 1, user_config.dir)
  return table.concat(args, "/")
end

function user_config:lua_path(...)
  local args = {...}
  table.insert(args, 1, user_config.lua_dir)
  return table.concat(args, "/")
end

function user_config:filetype_path(ft)
  return self:lua_path('config/filetypes', ft .. '.lua')
end

function user_config:config_path(modname)
  return self:lua_path('config', modname .. '.lua')
end

function user_config:set_filetypes()
  for f in vim.fs.dir(user_config.filetypes_dir) do
    if f:match('[.]lua$') then
      local ft = f:gsub('[.]lua$', '')
      local req = 'config.filetypes.' .. ft
      local ok, msg = pcall(require, req)
      if ok then user_config.filetype:new(msg) end
    end
  end
end

function user_config:set_buffer_groups()
  buffer_group.setup()
  autocmd('BufRead', '*', function (args)
    local ws = user_config:root_dir(args.buf)
    ws = ws or dirname(args.buf)

    if not ws then
      return
    end

    local exists = user_config.buffer_groups[ws]
    if exists and exists.group then
      return
    else
      local group = buffer_group(ws, ws)
      group:add(args.buf)
    end
  end)

  for name, _ in pairs(self.filetypes) do
    local group = buffer_group(name, function (bufnr)
      return buffer.filetype(bufnr) == name
    end)
  end
end

function user_config:load_plugins()
  require('config.lazy')
end

function user_config:set_opts()
  require('config.options')
end

function user_config:set_keymaps()
  vim.schedule(function ()
    require('config.keymaps')
  end)
end

function user_config:set_autocmds()
  vim.schedule(function ()
    require('config.autocmds')
  end)
end

function user_config:root_dir(bufnr)
  local bufname = buffer.name(bufnr)
  local ft = buffer.filetype(bufnr)
  local opts = user_config.dict.get(self.filetypes, {ft, 'root'}) or {}

  if not bufname:match('[a-zA-Z0-9]') then
    return false
  elseif not ft:match('[a-zA-Z0-9]') then
    return false
  end

  return buffer.workspace(bufnr, {
    pattern = user_config.dict.get(opts, {'root', 'pattern'}) or {'.git'},
    check_depth = user_config.dict.get(opts, {'root', 'check_depth'}) or 4,
  })
end

function user_config:on_exit(name, pattern, callback)
  local opts = {pattern = pattern}
  user_config.default_augroup:add_autocmd(name, 'VimLeavePre', callback, opts)
end

function user_config:query(...)
  return user_config.dict.get(user_config, {...})
end

function user_config:setup()
  self:set_filetypes()
  self:load_plugins()
  self:set_opts()
  self:set_autocmds()
  self:set_keymaps()
  self:set_buffer_groups()
end

return user_config
