require "nvim-utils.nvim"
require "nvim-utils.Autocmd"
require "nvim-utils.Job"
require "nvim-utils.Buffer"
require "nvim-utils.Buffer.Win"
require "nvim-utils.Kbd"

-- local utils = require 'nvim.utils.M.utils'
-- local cmds = require 'nvim-utils.M.commands'
-- local lsp = require 'nvim-utils.M.lsp'

local utils = reqloadfile "nvim.utils.M.utils"
local cmds = reqloadfile "nvim-utils.M.commands"
local lsp = reqloadfile "nvim-utils.M.lsp"
local M = class:new("Filetype", {
  "buffer",
  "from_dict",
  'jobs',
  'list',
  'main',
})

M.buffer = namespace 'Filetype.buffer'

function M:init(name)
  assert_is_a.string(name)

  -- if user.filetypes[name] then
  --   return user.filetypes[name]
  -- end

  local luafile = name .. ".lua"
  self.name = name
  self.requires = {
    config = 'core.filetype.' .. name,
    user_config = 'user.filetype.' .. name,
  }
  self.paths = {
    config_path = Path.join(vim.fn.stdpath "config", "lua", "core", "filetype", luafile),
    user_config = Path.join(user.user_dir, "user", 'filetype', luafile),
  }

  self.mappings = false
  self.autocmds = false
  self.buf_opts = false
  self.win_opts = false
  self.on = false
  self.augroup = 'UserFiletype' .. name:gsub('^[a-z]', string.upper)

  nvim.create.autocmd('FileType', {
    pattern = name,
    callback = function (_) self:require() end
  })

  return self
end

function M.buffer:__call(bufnr)
  if not Buffer.exists(bufnr) then
    return
  end

  local ft = Buffer.filetype(bufnr)
  if #ft == 0 then
    return
  end

  return M(ft)
end

function M:require(use_loadfile)
  local use = use_loadfile and reqloadfilex or requirex
  local core_config = use(self.requires.config) or {}
  local user_config = use(self.requires.user_config) or {}

  return dict.merge(self, { core_config, user_config })
end

function M:loadfile()
  return self:require(true)
end

function M:map(mode, ks, cb, opts)
  local mapping = Kbd(mode, ks, cb, opts)
  mappings.event = 'Filetype'
  mappings.pattern = self.name

  return mapping:enable()
end

function M:create_autocmd(callback, opts)
  opts = copy(opts or {})
  opts = is_string(opts) and {name = opts} or opts
  opts.pattern = self.name
  opts.group = self.augroup
  opts.callback = callback

  return Autocmd('FileType', opts)
end

function M:set_autocmds(mappings)
  mappings = mappings or {}
  dict.each(mappings, function (name, au)
  end)
end

function M:set_mappings(mappings)
  mappings = mappings or self.mappings or {}
  dict.each(mappings, function (key, value)
    value[4] = value[4] or {}
    value[4].event = 'Filetype'
    value[4].pattern = self.name
    value[4].name = key
    Kbd.map(unpack(value))
  end)
end
