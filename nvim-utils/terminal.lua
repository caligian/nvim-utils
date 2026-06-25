#!/usr/bin/env luajit

require 'nvim-utils.state'
require 'lua-utils.class'
require 'nvim-utils.buffer'
require 'nvim-utils.nvim'

local validate = require 'lua-utils.validate'
local path_utils = require 'lua-utils.path_utils'

---@class terminal.shape
---@field command? string
---@field cmd? string
---@field cwd? string
---@field root_dir? string
---@field id? number
---@field pid? number
---@field buffer? number

---@class terminal : terminal.shape
terminal = class 'terminal'

--- Since we are using nix-shell in some places, skip running the shell interpreter
---@type table<string,boolean>
terminal.valid_shell = { zsh = true, bash = true, csh = true, sh = true, tcsh = true, fish = true, tcsh = true }

---Contains terminal instances
---@type table<string,terminal>
user_config.terminal = user_config.terminal or {}
user_config.terminal_pid = user_config.terminal_pid or {}

local chansend = vim.api.nvim_chan_send
local jobstop = vim.fn.jobstop

function terminal:initialize(cmd, cwd)
  local cmd_is_fn = callable(cmd)

  assert(
    type(cmd) == 'string' or cmd_is_fn,
    'cmd: Expected string|fun(cwd: string): string, got ' .. tostring(cwd)
  )

  cwd = not cwd and vim.fn.getcwd() or cwd
  cmd = cmd_is_fn and cmd(cwd) or cmd

  assert(path_utils.is_dir(cwd), 'Invalid directory provided: ' .. cwd)

  self.command = cmd
  self.cmd = cmd
  self.cwd = cwd
  self.id = nil
  self.pid = nil
  self.buffer = nil
end

function terminal:send(s)
  return self:when_running(function(it)
    if it:is_invalid() then return false end
    if type(s) == 'table' then s = table.concat(s, "\n") end
    s = s .. "\r"
    chansend(it.id, s)

    return true
  end)
end

function terminal:send_region(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(_)
      local region = nvim.region(false)
      if region then
        return self:send(region)
      end
    end,
    err = function(msg)
      errorf(msg)
    end
  })
end

function terminal:send_buffer(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = buffer.string(buf)
      if not ok then
        error(msg)
      end

      local entire_buffer = msg
      self:send(entire_buffer)

      return entire_buffer
    end,
    err = function(msg)
      error(msg)
    end
  })
end

function terminal:send_current_line(bufnr)
  bufnr = bufnr or buffer.get_current_id()
  return buffer.get_id(bufnr, {
    ok = function(buf)
      local ok, msg = buffer.get_current_line(buf)
      if not ok then
        error(msg)
      end

      local line = msg
      self:send(line)

      return line
    end,
    err = function(msg)
      error(msg)
    end
  })
end

function terminal:send_ctrl_c()
  return self:send('')
end

function terminal:send_ctrl_z()
  return self:send('')
end

function terminal:send_ctrl_d()
  return self:send('')
end

---@return boolean
function terminal:stop()
  return self:when_running(function(it)
    jobstop(it.id)
    buffer.wipeout(it.buffer)

    it.id = nil
    it.pid = nil
    it.buffer = nil

    printf(
      'Stopped REPL with command %s @ %s',
      self.cmd,
      self.cwd:gsub(os.getenv('HOME'), '~')
    )

    return true
  end)
end

function terminal:get_status_code(timeout)
  timeout = timeout or 0
  if self.id then
    return vim.fn.jobwait({ self.id }, timeout)[1]
  else
    return false
  end
end

---Is terminal running?
---@return boolean
function terminal:is_running()
  if not self.id then
    return false
  end

  return self:get_status_code(0) == -1
end

---@param callback fun(x: terminal.shape)
---@return any
function terminal:when_running(callback)
  local ok = self:is_running()
  if ok and callback then
    return callback(self)
  else
    return false
  end
end

---@param callback fun(x: terminal.shape)
---@return any
function terminal:unless_running(callback)
  local ok = not self:is_running()
  if ok and callback then
    return callback(self)
  else
    return false
  end
end

function terminal:is_invalid()
  if not self.id then
    return true
  else
    return self:get_status_code(0) == -3
  end
end

function terminal:is_valid()
  if not self.id then
    return false
  else
    return not self:is_invalid()
  end
end

function terminal:get_exit_status()
  if not self.id then
    return false
  else
    local status = self:get_status_code()
    if status < 0 then return false end
    return status
  end
end

---Returns job id
---@param self terminal.shape
---@param shell? boolean
---@return boolean, number|string
function terminal:open(shell)
  local bufnr = vim.api.nvim_create_buf(false, true)
  return buffer.call(bufnr, function()
    local nix_file = self.cwd .. '/shell.nix'
    local is_nix_dir = path_utils.is_file(nix_file)

    if not is_nix_dir then
      nix_file = self.cwd .. '/default.nix'
      is_nix_dir = path_utils.is_file(nix_file)
    end

    if not is_nix_dir then
      nix_file = os.getenv("HOME") .. '/shell.nix'
    end

    local env = vim.fn.environ()
    env.TERM = "xterm-256color"
    local cmd = sprintf('nix-shell %s', nix_file)

    ---@diagnostic disable-next-line
    local job_id = vim.fn.jobstart(cmd, { cwd = self.cwd, env = env, term = true })

    if job_id == 0 or job_id == -1 then
      local msg = sprintf("Could not run command `%s' @ %s", self.cmd, self.cwd)
      message.fatal(msg)
      error(msg)
    end

    if not shell then
      message.ok('Starting terminal session with cmd: %s')
      chansend(job_id, self.cmd .. "\r")
    end

    self.id = job_id
    self.buffer = bufnr
    self.pid = vim.fn.jobpid(self.id)

    vim.keymap.set(
      { 'n' }, 'q',
      ':call HideWindowIfPossible()<CR>',
      { desc = 'hide buffer', buffer = self.buffer }
    )

    vim.keymap.set(
      { 'n' }, 'Q',
      ':call WipeoutBufferWindowIfPossible()<CR>',
      { desc = 'hide buffer', buffer = self.buffer }
    )

    return self.id
  end)
end

---@param shell boolean?
---@return boolean
function terminal:start(shell)
  if self:is_running() then
    return true
  end

  local cmd, cwd = self.cmd, self.cwd
  local ok, msg = self:open(self, shell)

  if not ok then
    return false, msg
  end

  ok = self:when_running(function(it)
    autocmd.set(
      'TermClose',
      function(args)
        ok, _ = pcall(buffer.rm, args.buf)
        if not ok then
          printf('Could not delete terminal for %s', it.cmd)
        end
      end,
      {
        buffer = it.buffer,
        desc = sprintf('Delete terminal buffer for %s', it.cmd)
      }
    )

    user_config.terminal[self.id] = it
    user_config.terminal_pid[self.pid] = it

    return true
  end)

  if not ok then
    return false, sprintf('Could not start terminal with `%s` @ buffer %d', cmd, self.buffer)
  end

  return true, nil
end

function terminal:is_visible()
  return self:when_running(function(it)
    return buffer.is_visible(it.buffer)
  end)
end

function terminal:split(direction, resize)
  return self:when_running(function(it)
    if not it:is_visible() then
      buffer.split(buffer.get_current(), direction, resize)
      buffer.set_current(it.buffer)
      return true
    else
      return false
    end
  end)
end

function terminal:split_right(resize)
  return self:split('right', resize)
end

function terminal:split_below(resize)
  return self:split('split', resize or -5)
end

function terminal:hide()
  return self:when_running(function(it)
    if buffer.is_visible(it.buffer) then
      buffer.hide(it.buffer, true)
    end
  end)
end

-- local ok, git_dir = buffer.in_git_dir()
-- if ok then
--   luarepl = terminal('luajit', git_dir)
--   print(luarepl.cwd)
--   print(luarepl:start())
--   pp(luarepl:get_status_code())
--   luarepl:split()
-- end
--
return terminal
