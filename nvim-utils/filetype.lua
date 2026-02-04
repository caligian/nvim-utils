local utils = require 'lua-utils'
local types = utils.types
local dict = utils.dict
local list = utils.list
local validate = utils.validate
local class = utils.class
local augroup = require('nvim-utils.augroup')
local buffer = require('nvim-utils.buffer')
local buffer_group = require 'nvim-utils.buffer_group'
local keymap = require 'nvim-utils.keymap'

--- Valid options
-- {
--   keymaps = {{'n', '<leader>ff', printf}},
--   autocmds = {function() vim.o.something = true end},
--   buffer = {
--     vars = {a = 1, b = 2, c = 3},
--     opts = {c = 2, d = 10}
--   },
--   root = {
--     pattern = {'.git'},
--     check_depth = 4,
--   },
--   lsp = {'jedi_language_server', ...lsp_settings},
--   shell_command = 'bash',
--   repl = {
--     command = 'ipython3', -- dir will be set to root
--     input = {
--       use_file = true,
--       file_string = '%%load %s',
--       apply = function(lines) return lines end
--     },
--   }
-- }

local filetype = class 'filetype'

local function update_lsp_config(opts)
  local root_merged = false
  local merge_root_config = function(config)
    if config.root_markers then
      dict.set(opts, {'root', 'pattern'}, config.root_markers, true)
    end
  end
  local merge_config = function(name, lsp_opts)
    local ok, config = pcall(require, 'nvim-lspconfig.lsp.' .. name)
    if ok then 
      if not root_merged then
        merge_root_config(config)
        root_merged = true
      end
      dict.merge(lsp_opts, config) 
    end
  end
  local spec = opts.lsp

  if not spec or dict.size(spec) == 0 then
    return
  end

  if type(spec[1]) == 'table' then
    validate.server(spec, types.table)
    for _, server in ipairs(spec) do
      merge_config(server[1], server)
    end
  else
    validate.server(spec[1], 'string')
  end
end

function filetype:initialize(opts)
  if types.string(opts) then
    opts = require('config.filetypes.' .. opts)
  end

  validate.opts(opts, {
    name = types.string,
    opt_keymaps = types.dict,
    opt_autocmds = types.dict,
    opt_buffer = {
      opt_vars = types.dict,
      opt_opts = types.dict
    },
    opt_root = {
      opt_pattern = types.list,
      opt_check_depth = types.number
    },
    opt_lsp = types.table,
    opt_repl = {
      command = types.string,
      opt_input = {
        opt_use_file = types.boolean,
        opt_file_string = types.string,
        opt_apply = types.fun
      }
    }
  })

  update_lsp_config(opts)
  dict.merge(self, opts)

  if self.lsp and dict.size(self.lsp) > 0 then
    if type(opts.lsp[1]) == 'string' then
      validate.server(opts.lsp[1], 'string')
    else
      for _, spec in ipairs(opts.lsp) do
        validate.server(spec[1], 'string')
      end
    end
  end

  self.require_path = 'config.filetypes.' .. self.name
  self.augroup = augroup('user_config.filetype.' .. self.name)
  self.loaded = false

  dict.set_unless(self, {'root', 'pattern'}, {'.git'}, true)
  dict.set_unless(self, {'root', 'check_depth'}, 4)
  self:setup()

  dict.set_unless(self, {'root', 'buffer_groups'}, {})
  user_config.filetypes[self.name] = self
end

function filetype:get_lsp_config()
  local config = self.lsp
  if not config or dict.size(config) == 0 then
    return
  end

  config = vim.deepcopy(config)
  if type(config[1]) == 'string' then
    local server = table.remove(config, 1)
    return {{server, config}}
  else
    local out = {}
    for _, spec in ipairs(self.lsp) do
      local server = spec[1]
      table.remove(spec, 1)
      local server_config = spec
      out[#out+1] = {server, server_config}
    end

    return out
  end
end

function filetype:has_lsp_config()
  return types.table(self.lsp)
end

function filetype:require()
  return require(self.require_path)
end

function filetype:set_autocmds()
  if not self.autocmds then
    return
  end

  for name, callback in pairs(self.autocmds) do
    local opts = {name = name, desc = name}
    self.augroup:add_autocmd('FileType', self.name, callback, opts)
  end

  return true
end

function filetype:set_keymaps()
  if self.keymaps then
    self:add_keymaps(self.keymaps)
    return true
  end
end

function filetype:set_buf_vars()
  self.augroup:add_autocmd('FileType', self.name, function()
    if self.buffer and self.buffer.vars then
      local curbuf = buffer.current()
      for key, value in pairs(self.buffer.vars) do
        buffer.set_var(curbuf, key, value)
      end
    end
  end, {name = 'buffer.variables'})
end

function filetype:set_buf_opts()
  self.augroup:add_autocmd('FileType', self.name, function()
    if self.buffer and self.buffer.opts then
      local curbuf = buffer.current()
      for key, value in pairs(self.buffer.opts) do
        buffer.set_opt(curbuf, key, value)
      end
    end
  end, {name = 'buffer.options'})
end

function filetype:add_autocmd(callback, opts)
  opts = opts or {}
  validate.opts(opts, 'table')

  opts = vim.deepcopy(opts)
  opts.pattern = self.name

  self.augroup:add_autocmd('FileType', self.name, callback, opts)
end

function filetype:add_keymap(mode, lhs, rhs, opts)
  opts = vim.deepcopy(opts or {})
  validate.opts(opts, 'table')

  opts.filetype = self.name
  opts.group = self.augroup.name

  return keymap.set(mode, lhs, rhs, opts)
end

function filetype:add_keymaps(specs)
  for name, spec in pairs(specs) do
    local mode, lhs, rhs, opts = unpack(spec)
    opts = vim.deepcopy(opts)
    opts.name = name
    self:add_keymap(mode, lhs, rhs, opts)
  end
end

function filetype:delete_autocmd(name_or_id)
  self.augroup:delete_autocmd(name_or_id)
end

filetype.del_autocmd = filetype.delete_autocmd

function filetype:query(...)
  return dict.get(self, {...})
end

function filetype:root_dir(bufnr)
  local bufname = buffer.name(bufnr)
  local ft = buffer.filetype(bufnr)
  local root_opts = self.root or {
    pattern = {'.git'},
    check_depth = 4
  }

  if not ft:match('[a-zA-Z0-9]') then
    return false
  elseif not bufname:match('[a-zA-Z0-9]') then
    return false
  end

  local bgs = self.root.buffer_groups
  local ws = buffer.workspace(bufnr, root_opts)
  if not bgs[ws] then
    bgs[ws] = buffer_group(ws, ws)
  end
end

function filetype:setup()
  self:set_buf_vars()
  self:set_buf_opts()
  self:set_autocmds()
  self:set_keymaps()
  self.loaded = true
  return self
end

-- Used for project files who do not have a ftconfig
if not user_config.filetypes.shell then
  user_config.filetypes.shell = filetype {
    name = 'shell',
    root = {pattern = {'.git'}, check_depth = 4},
    repl = {command = user_config.shell_command or 'bash'}
  }
end

function filetype.buf_get(buf)
  buf = buf or vim.fn.bufnr()
  local ft = buffer.filetype(buf)
  return user_config.filetypes[ft]
end

return filetype
