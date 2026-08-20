require 'lua-utils'

local dict = require 'lua-utils.dict'
local list = require 'lua-utils.list'
local validate = require 'lua-utils.validate'

local autocmd = require 'nvim-utils.autocmd'
local augroup = require 'nvim-utils.augroup'

require 'nvim-utils.buffer'
require 'nvim-utils.buffer_group'
require 'nvim-utils.keymap'
require 'nvim-utils.command'

---@class filetype.keymap.spec
---@field [1] table|string
---@field [2] string
---@field [3] string|callable
---@field [4]? keymap.opts

---@class filetype.autocmd.spec
---@field [1] autocmd.event
---@field [2] autocmd.callback
---@field [3]? autocmd.opts

---@class filetype.command.spec
---@field [1] table|string

---@class filetype.buffer
---@field var? table<string,any>,
---@field opt? table<string,any>

---@class filetype.root
---@field pattern string|[]string
---@field check_depth? number (default: 4)

---@alias filetype.terminal_dict table<string,terminal>
---@alias filetype.repl_dict     table<string,repl>
---@alias filetype.compiler_dict table<string,terminal>
---@alias filetype.keymap_dict   table<string,filetype.keymap.spec>
---@alias filetype.command_dict  table<string,command.spec>
---@alias filetype.autocmd_dict  table<string,filetype.autocmd.spec>

---@class filetype.state
---@field terminal filetype.terminal_dict
---@field repl filetype.repl_dict
---@field compiler filetype.compiler_dict
---@field command filetype.command_dict
---@field autocmd filetype.autocmd_dict
---@field keymap filetype.keymap_dict

---@class filetype.compile.cmd.args
---@field buf number
---@field file string

---@alias filetype.compile.run string|(fun(args: filetype.compile.cmd.args): string)
---@alias filetype.compile.pattern string|(fun(args: filetype.compile.cmd.args): boolean)

---@class filetype.repl
---@field cmd? repl.cmd
---@field command? repl.cmd
---@field input? repl.opts.input
---@field root? repl.opts.root

---@class filetype.class : class
---@field name string
---@field keymap? table<string, keymap.shape>
---@field autocmd? table<string, autocmd.shape>
---@field command? table<string, command.shape>
---@field run? table<filetype.compile.pattern, filetype.compile.run>
---@field root? filetype.root
---@field buffer? filetype.buffer
---@field lsp? table<string,table>
---@field state filetype.state
---@field repl filetype.repl

---@class filetype : filetype.class : instance

---@type filetype.class
---@overload fun(name: string, specs: filetype.class): filetype
filetype = class('filetype')

---Validators for filetype configs
filetype.validator = {}

---Validator for filetype specification
filetype.validator.self = {
  opt_template = 'table',
  opt_keymap = 'table',
  opt_autocmd = 'table',
  opt_run = 'table',
  opt_repl = {
    command = union('string', 'table', 'function'),
    opt_input = {
      opt_file = {
        opt_format = 'string',
        opt_use = 'boolean',
      },
      opt_apply = 'callable',
    }
  },
  opt_buffer = {
    opt_var = 'table', opt_opt = 'table'
  },
  opt_lsp = 'table',
  opt_root = {
    opt_pattern = union('string', 'table'),
    opt_check_depth = 'number'
  }
}

filetype.validator.autocmd = {
  event = union('table', 'string'),
  run = union('string', 'function'),
  opt_opts = 'table',
}

filetype.validator.keymap = {
  mode = union('table', 'string'),
  lhs = 'string',
  rhs = union('string', 'function'),
  opt_opts = 'table',
}

---@type table<string,filetype>
user_config.filetype = user_config.filetype or {}

---Valid options
--[[
filetype('lua', {
  keymaps = {{'n', '<leader>ff', printf}},
  autocmds = {function() vim.o.something = true end},
  buffer = {
    vars = {a = 1, b = 2, c = 3},
    opts = {c = 2, d = 10}
  },
  root = {
    pattern = {'.git'},
    check_depth = 4,
  },
  -- Default run functions for these buffers
  run = {
    -- Default for all programs
    all = {
      cond = '.*.lua$',
      cmd  = 'luajit %s'
    },
    --- Match a filepath. Here, source the file instead of running it with luajit
    ['/nvim-utils/.*lua$'] = {
       -- args: {buf = {bufnr}, file = {bufname}}
       cmd = function (args)
          local f = loadstring(slurp(args.filename))
          local ok, msg = f()

          if not ok then
            error(msg)
          end
       end
    }
  },
  lsp = {'jedi_language_server', ...lsp_settings},
  repl = {
    command = 'ipython3', -- dir will be set to root
    input = {
      use_file = true,
      file_string = '%%load %s',
      apply = function(lines) return lines end
    },
  }
})
---]]


function filetype:initialize(ft, config)
  self.name = ft
  self.keymap = {}
  self.autocmd = {}
  self.run = {}
  self.augroup = augroup.set('user_config.filetype.' .. self.name, true, {})
  self.template = user_config.template[self.name]
  self.root = { pattern = { ".git" }, check_depth = 4 }

  dict.mergef(self, config)
  dict.set_unless(self, { 'root', 'pattern' }, { '.git' }, true)
  dict.set_unless(self, { 'root', 'check_depth' }, 4)
  dict.set_unless(self, { 'root', 'buffer_group' }, {})

  user_config.filetype[self.name] = self
end

function filetype:has_lsp()
  return self.lsp ~= nil
end

function filetype:fix_lsp()
  if self.lsp == nil or size(self.lsp) == 0 then
    return
  end

  if type(self.lsp) == 'string' then
    self.lsp = { [self.lsp] = {} }
  elseif is.pure_list(self.lsp) then
    local lsp = self.lsp
    self.lsp = {}

    for i = 1, #lsp do
      self.lsp[lsp[i]] = {}
    end

    return self:fix_lsp()
  else
    assert(is.pure_dict(self.lsp))
  end
end

---@param self filetype
---@param key string
---@return string
local function make_name(self, key)
  return sprintf('filetype.%s.%s', self.name, key)
end

function filetype:set_keymap(name, modes, lhs, rhs, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.name = sprintf('filetype.%s.%s', self.name, name)
  opts.event = 'filetype'
  opts.pattern = self.name
  local kbd = keymap.set(modes, lhs, rhs, opts)
  self.keymap[name] = kbd

  return kbd
end

---@param name string
---@param event string|string[]
---@param callback function|string
---@param opts? autocmd.opts
function filetype:set_autocmd(name, callback, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.name = make_name(self, name)
  opts.pattern = self.name
  self.augroup:append('filetype', callback, opts)
end

function filetype:set_keymaps(specs)
  self.keymap = self.keymap or {}
  specs = dict.merge(vim.deepcopy(specs or {}), self.keymap)

  for name, specs in pairs(self.keymap) do
    self:set_keymap(name, unpack(specs))
  end
end

---@class filetype.autocmd.shape
---@field [1] string|function
---@field [2]? autocmd.opts

---@param specs? table<string,filetype.autocmd.shape|function>
---@return table<string,autocmd>?
function filetype:set_autocmds(specs)
  self.autocmd = self.autocmd or {}
  specs = dict.merge(vim.deepcopy(specs or {}), self.autocmd)

  local res = {}
  for key, value in pairs(specs) do
    local name = make_name(self, key)
    if callable(value) then
      res[key] = autocmd.set('filetype', value, { pattern = self.name, desc = name, name = name })
    elseif type(value) == 'string' then
      res[key] = autocmd.set('filetype', value, { pattern = self.name, desc = name, name = name })
    else
      local callback, opts = unpack(value)
      opts = vim.deepcopy(opts or {})
      opts.name = make_name(self, key)
      opts.pattern = self.name
      res[key] = autocmd.set('filetype', callback, opts)
    end
  end

  return res
end

function filetype:set_buf_vars()
  if self.buffer and self.buffer.var then
    self:set_autocmd('buffer_vars', function()
      local curbuf = buffer.get_current_id()
      for key, value in pairs(self.buffer.var) do
        buffer.set_var(curbuf, key, value)
      end
    end)
  end
end

function filetype:set_buf_opts()
  if self.buffer and self.buffer.opt then
    self:set_autocmd('buffer_opts', function(args)
      for key, value in pairs(self.buffer.opt) do
        buffer.set_opt(args.buf, key, value)
      end
    end)
  end
end

function filetype:query(ks)
  ks = type(ks) ~= 'table' and { ks } or ks
  return dict.get(self, ks)
end

function filetype:fix_root()
  local root_opts = self.root or {
    pattern = { '.git' },
    check_depth = 4
  }

  if type(root_opts) == 'string' then
    root_opts = { pattern = root_opts }
  elseif type(root_opts) == 'number' then
    root_opts = { pattern = { '.git' }, check_depth = root_opts }
  elseif type(root_opts.pattern) == 'string' then
    root_opts.pattern = { root_opts.pattern }
  end

  self.root = root_opts
  return self.root
end

---@param bufnr number
---@param pat? []string|string (default: {'.git'})
---@param depth? number (default: 4)
---@return string?
function filetype:get_root_dir(bufnr, pat, depth)
  local ok, msg = buffer.is_valid(bufnr)
  if not ok then
    return false, msg
  end

  self.root = self.root or { pattern = { ".git" }, check_depth = 4 }
  local ws = buffer.get_root_dir(
    bufnr,
    pat or self.root.pattern,
    depth or self.root.check_depth
  ) or buffer.dirname(bufnr)

  if true then

  end

  local bg_name = sprintf("%s.%s", self.name, ws)
  if not user_config.buffer_group[bg_name] then
    buffer_group(bg_name, ws)
  end

  return ws
end

---Load the configuration file
---@return filetype
function filetype:require()
  local config = require('config.filetype.' .. self.name)
  dict.mergef(self, config)
  -- self:update()

  return self
end

function filetype:setup(force)
  if force or not self.loaded then
    self:require()
    self:fix_lsp()
    self:fix_root()
    self:set_buf_vars()
    self:set_buf_opts()
    self:set_autocmds()
    self:set_keymaps()
    self.loaded = true
  end

  return self
end

return filetype
