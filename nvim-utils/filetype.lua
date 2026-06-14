require 'nvim-utils.state'

local types = require 'lua-utils.types'
local dict = require 'lua-utils.dict'
local list = require 'lua-utils.list'

local path_utils = require 'lua-utils.path_utils'
local validate = require 'lua-utils.validate'
local class = require 'lua-utils.class'

require 'nvim-utils.augroup'
require 'nvim-utils.buffer'
require 'nvim-utils.buffer_group'
require 'nvim-utils.keymap'
require 'nvim-utils.autocmd'

---@class filetype
---@field keymaps? filetypeKeymaps
---@field autocmds? filetypeAutocmds
---@field root? filetypeRoot
---@field buffer? filetypeBuffer
---@field lsp? table<string,table>
---@field shell_command? string (default: bash)
filetype = class('filetype')

---Validator for filetype specification
filetype.validator = {
  opt_keymaps = { keymap_config, 'table' },
  opt_autocmds = { autocmd_config, 'table' },
  opt_repl = {
    repl_config, {
      command = 'string',
      opt_input = {
        opt_use_file = 'boolean',
        opt_file_string = 'string',
        opt_apply = 'function',
      }
    }
  },
  opt_buffer = {
    buffer_config,
    { opt_vars = 'table', opt_opts = 'table' }
  },
  opt_lsp = { lsp_config, 'table' },
  opt_root = {
    root_config,
    {
      opt_pattern = types.union('string', 'table'),
      opt_check_depth = 'number'
    }
  }
}
user_config.filetype = user_config.filetype or {}

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

---@class filetypeKeymap
---@field [1] string|[]string
---@field [2] string
---@field [3] function|string
---@field [4]? table

---@alias filetypeKeymaps table<string|number,filetypeKeymap>

---@class filetypeAutocmd
---@field [1]? function|[]function
---@field opts? table

---@alias filetypeAutocmds table<string|number,filetypeAutocmd>

---@class filetypeBuffer
---@field vars? table<string,any>,
---@field opts? table<string,any>

---@class filetypeRoot
---@field pattern string|[]string
---@field check_depth? number (default: 4)

function filetype:initialize(ft, config)
  self.name = ft
  self.keymap = {}
  self.autocmd = {}
  self.augroup = augroup.set('user_config.filetype.' .. self.name, true, {})

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
    self.lsp = {[self.lsp] = {}}
  elseif types.pure_list(self.lsp) then
    local lsp = self.lsp
    self.lsp = {}

    for i=1, #lsp do
      self.lsp[lsp[i]] = {}
    end

    return self:fix_lsp()
  else
    assert(types.pure_dict(self.lsp))
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
---@param opts autocmdOpts
function filetype:set_autocmd(name, callback, opts)
  opts = opts or {}
  opts = vim.deepcopy(opts)
  opts.name = make_name(self, name)
  opts.pattern = self.name
  self.augroup:append('filetype', callback, opts)

  return au
end

function filetype:set_keymaps(specs)
  self.keymap = self.keymap or {}
  specs = dict.merge(vim.deepcopy(specs or {}), self.keymap)

  for name, specs in pairs(self.keymap) do
    self:set_keymap(name, unpack(specs))
  end
end


---@class filetypeAutocmdSpec
---@field [1] string|function
---@field [2]? autocmdOpts

---@param specs table<string,filetypeAutocmdSpec|function>
---@return table<string,autocmd>?
function filetype:set_autocmds(specs)
  self.autocmd = self.autocmd or {}
  specs = dict.merge(vim.deepcopy(specs or {}), self.autocmd)

  local res = {}
  for key, value in pairs(specs) do
    local name = make_name(self, key)
    if callable(value) then
      res[key] = autocmd.set('filetype', value, {pattern = self.name, desc = name, name = name})
    elseif type(value) == 'string' then
      res[key] = autocmd.set('filetype', value, {pattern = self.name, desc = name, name = name})
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
  if self.buffer and self.buffer.vars then
    self:set_autocmd('buffer_vars', function()
        local curbuf = buffer.get_current_id()
        for key, value in pairs(self.buffer.vars) do
          buffer.set_var(curbuf, key, value)
        end
      end)
  end
end

function filetype:set_buf_opts()
  if self.buffer and self.buffer.opts then
    self:set_autocmd('buffer_opts', function()
        local curbuf = buffer.get_current_id()
        for key, value in pairs(self.buffer.opts) do
          buffer.set_opt(curbuf, key, value)
        end
      end)
  end
end

function filetype:query(ks)
  ks = type(ks) ~= 'table' and {ks} or ks
  return dict.get(self, ks)
end

function filetype:fix_root()
  local root_opts = self.root or {
    pattern = { '.git' },
    check_depth = 4 
  }

  if type(root_opts) == 'string' then
    root_opts = {pattern = root_opts}
  elseif type(root_opts) == 'number' then
    root_opts = {pattern = {'.git'}, check_depth = root_opts}
  elseif type(root_opts.pattern) == 'string' then
    root_opts.pattern = {root_opts.pattern}
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

  local ft
  ok, msg = buffer.get_filetype(bufnr)

  if not ok then
    return false, sprintf('buffer[%d]: Expected filetype as %s, got %s', bufnr, self.name, msg)
  else
    ft = msg
    if #ft == 0 then
      return false, sprintf('buffer[%d]: Has empty filetype. Expected filetype %s', bufnr, self.name)
    end
  end

  local bufname = buffer.get_name(bufnr)
  local bgs = self.root.buffer_group
  local ws = buffer.get_root_dir(bufnr, root_opts.pattern, root_opts.check_depth)

  if not bgs[ws] then
    bgs[ws] = buffer_group(ws, ws)
  end

  return ws
end

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

---Other class methods and static methods
filetype.utils = {}
local utils = filetype.utils

---@param ... []string|string|number
---@return any
function utils.get(...)
  local ks = list.flatten {...}
  return dict.get(user_config.filetype, ks)
end

---@param bufnr? number
---@param ... []string|string|number
---@return any
function utils.buffer_get(bufnr, ...)
  bufnr = bufnr or vim.fn.bufnr()
  local ks = list.flatten({bufnr}, {...})

  return buffer.get_id(bufnr, {
    ok = function (buf)
      return utils.get(buf, ks)
    end,
    err = function (msg)
      return msg
    end
  })
end

---@param ft string
---@return filetype?
function utils.exists(ft)
  return user_config.filetype[ft]
end

---@return []string
function utils.list_builtin()
  local ft_path = user_config.path.dir.filetype
  local ft_paths = path_utils.glob(ft_path .. '/*.lua')
  local res = {}

  for _, path in ipairs(ft_paths) do
    local ft = path_utils.basename(path):gsub('%.lua$', '')
    res[#res+1] = ft
  end

  return res
end

---@return table<string,filetype>
function utils.setup_builtin()
  local res = {}

  for _, ft in ipairs(utils.list_builtin()) do
    local x = filetype(ft)
    x:setup()
    res[x.name] = x
  end

  return res
end

--- Used for project files who do not have a ftconfig
if not user_config.filetype.shell then
  ---@type filetype
  user_config.filetype.sh = filetype('sh'):setup()
end

return filetype
