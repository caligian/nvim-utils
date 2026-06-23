local utils = require 'lua-utils'
local class = utils.class
local types = utils.types
local dict = utils.dict
local validate = utils.validate
local buffer = require 'nvim-utils.buffer'
local terminal = require('nvim-utils.terminal')

user_config.repl.repl = user_config.repl.repl or {}
user_config.repl.shell = user_config.repl.shell or {}

local repls = user_config.repl.repl
local shells = user_config.repl.shell

---@class repl.opts.root
---@field pattern? string|string[]
---@field check_depth? number

---@class repl.opts.input
---@field use_file? string|string[]
---@field apply? function
---@field file_string? string

---@class repl.opts
---@field shell? boolean
---@field root?  repl.opts.root
---@field input? repl.opts.input
---@field filetype? string

---@class repl.shape : terminal.shape
---@field shell? boolean
---@field root_pattern? string|string[]
---@field root_check_depth? string|string[]
---@field input_use_file? string|string[]
---@field input_apply? function
---@field input_file_string? string
---@field filetype? string

---@class repl : repl.shape
---@overload fun(bufnr: number, opts?: table): repl.shape
repl = class('repl', terminal)

-- opts = {
--   command = types.string,
--   root = {
--     pattern = types.list_of(types.string),
--     check_depth = types.number
--   },
--   input = {
--     use_file = types.boolean,
--     file_string = types.string,
--     apply = types.fun
--   }
-- }

function repl:initialize(bufnr, opts)
  bufnr = bufnr or vim.fn.bufnr()
  if not buffer.exists(bufnr) then
    errorf('buffer[%d] does not exist', bufnr)
  end

  opts = opts or {}

  local _, ft = buffer.get_filetype(bufnr)
  local ftobj = user_config.filetype[ft]
  local ftobj_root = ftobj and ftobj.root
  local ftobj_repl = ftobj and ftobj.repl

  local root = opts.root or ftobj_root or {}
  local input = opts.input or (ftobj_repl and ftobj_repl.input) or {}
  local cmd = opts.command or (ftobj_repl and ftobj_repl.command)

  if opts.shell then
    cmd = vim.env.shell
    self.shell = true
  end

  if cmd == nil then
    errorf("No REPL specification exists for filetype %s", ft)
  end

  local wd = opts.root_dir or opts.cwd or buffer.get_root_dir(
    bufnr, root.pattern, root.check_depth
  ) or buffer.dirname(bufnr)

  self.root_pattern = root.pattern or { ".git" }
  self.root_check_depth = root.check_depth or 4
  self.input_use_file = input.use_file
  self.input_file_string = input.file_string
  self.input_apply = input.apply
  self.filetype = ft

  if self.shell then
    shells[wd] = self
  else
    repls[ft] = repls[ft] or {}
    repls[ft][wd] = self
  end

  terminal.initialize(self, cmd, wd)
end

-- function repl:initialize(cwd, root_opts, input_opts)
--   opts = opts or {}
--   self.root_pattern = dict.get(opts, { 'root', 'pattern' })
--   self.root_check_depth = dict.get(opts, { 'root', 'check_depth' })
--   self.input_use_file = dict.get(opts, { 'input', 'use_file' })
--   self.input_file_string = dict.get(opts, { 'input', 'file_string' })
--   self.input_apply = dict.get(opts, { 'input', 'apply' })
--   self.filetype = opts.filetype
--   self.shell = opts.shell
--
--   terminal.initialize(self, opts.command or opts.cmd, cwd)
--
--   if self.shell then
--     self.cmd = user_config.shell
--     self.command = self.cmd
--     user_config.repl.shell[cwd] = self
--   else
--     validate.filetype(opts.filetype, types.string)
--     user_config.repl.repl[cwd] = user_config.repl.repl[cwd] or {}
--     user_config.repl.repl[cwd][self.filetype] = self
--   end
-- end
--
function repl:exists(callback)
  local exists
  if self.shell then
    exists = user_config.repl.shell[self.cwd]
  else
    exists = dict.get(
      user_config.repl.repl,
      { self.cwd, self.filetype }
    )
  end

  if exists then
    return defined(callback) and callback(exists) or exists
  else
    return false
  end
end

function repl:send(s)
  if self.input_use_file and not self.shell then
    local filename = vim.fn.tempname()
    local fh = io.open(filename, 'w')

    fh:write(s)
    fh:close()

    validate.file_string(self.input_file_string, 'string')
    s = self.input_file_string:format(filename)

    local timer = vim.uv.new_timer()
    timer:start(10000, 0, vim.schedule_wrap(function()
      pcall(vim.fs.rm, filename)
      timer:stop()
      timer:close()
    end))
  end

  return terminal.send(self, s)
end

return repl
