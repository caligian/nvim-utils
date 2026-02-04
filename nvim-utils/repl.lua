local utils = require 'lua-utils'
local class = utils.class
local types = utils.types
local dict = utils.dict
local validate = utils.validate
local buffer = require 'nvim-utils.buffer'
local terminal = require('nvim-utils.terminal')
local repl = class('repl', terminal)

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
--
function repl:initialize(cwd, opts)
  self.root_pattern = dict.get(opts, {'root', 'pattern'})
  self.root_check_depth = dict.get(opts, {'root', 'check_depth'})
  self.input_use_file = dict.get(opts, {'input', 'use_file'})
  self.input_file_string = dict.get(opts, {'input', 'file_string'})
  self.input_apply = dict.get(opts, {'input', 'apply'})
  self.filetype = opts.filetype or opts.ft
  self.ft = self.filetype
  self.shell = opts.shell

  terminal.initialize(self, opts.command or opts.cmd, cwd)

  if self.shell then
    self.cmd = user_config.shell_command or 'bash'
    self.command = self.cmd
    user_config.repls.shells[cwd] = self
  else
    validate.filetype(opts.filetype, types.string)
    user_config.repls.repls[cwd] = user_config.repls.repls[cwd] or {}
    user_config.repls.repls[cwd][self.filetype] = self
  end
end

function repl:exists(callback)
  local exists
  if self.shell then
    exists = user_config.repls.shells[self.cwd]
  else
    exists = dict.get(
      user_config.repls.repls,
      {self.cwd, self.filetype}
    )
  end

  if exists then
    return ifelse(callback, callback(exists), exists)
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
    timer:start(10000, 0, vim.schedule_wrap(function ()
      pcall(vim.fs.rm, filename)
      timer:stop()
      timer:close()
    end))
  end

  return terminal.send(self, s)
end

function repl.get(bufnr, shell, running)
  local cwd = user_config:root_dir(bufnr)
  if not cwd then
    return false
  end

  local exists
  if shell then
    exists = user_config.repls.shells[cwd]
  else
    local ft = buffer.filetype(bufnr)
    exists = dict.get(user_config.repls.repls, {cwd, ft})
  end

  if exists then
    if running and not exists:running() then
      return false
    else
      return exists
    end
  end
end

function repl.create(bufnr, shell)
  local exists = repl.get(bufnr, shell, true)
  if exists then
    return exists
  end

  local ws = user_config:root_dir(bufnr)
  if not ws then
    return false
  end

  local ft = buffer.filetype(bufnr)
  local opts = dict.get(user_config.filetypes, {ft, 'repl'})
  opts = opts or dict.get(user_config.filetypes, {'shell', 'repl'})

  if not opts then
    return false
  elseif shell then
    opts = dict.merge(vim.deepcopy(opts), {shell = true})
  else
    opts = dict.merge(vim.deepcopy(opts), {filetype = ft})
  end

  return repl(ws, opts)
end

function repl.start_shell()
  if not user_config.repls.shell then
    user_config.repls.shell = terminal(
      user_config.shell_command,
      os.getenv('HOME')
    )
  end
  local term = user_config.repls.shell
  if not term then
    return false
  else
    term:start()
  end
end

return repl
