#!/usr/bin/env luajit

require 'lua-utils'
require 'nvim-utils.state'

local path = require 'lua-utils.path_utils'
local autocmd = require 'nvim-utils.autocmd'
local nvim = require 'nvim-utils.nvim'
local buffer = require 'nvim-utils.buffer_utils'
local bufcall = vim.api.nvim_buf_call

---@alias terminal.cmd.cond string|string[]|(fun(args: terminal.cmd.args): boolean)
---@alias terminal.cmd.maker string|string[]|(fun(args: terminal.cmd.args): string)
---@alias terminal.cmd string|string[]|table<terminal.cmd.cond,terminal.cmd.maker>

---@class terminal.cmd.args
---@field buf integer
---@field file string
---@field cwd string

---@class terminal : terminal.class : instance
---@class terminal.class : class
---@field cmd? terminal.cmd
---@field nix_cmd? string
---@field cwd string
---@field display_cwd string
---@field id? integer
---@field pid? integer
---@field buffer? integer
---@overload fun(cwd?: string, cmd?: terminal.cmd): terminal
local terminal = class 'terminal'
local state = user_config.state.terminal
local by_id = state.by_id
local by_pid = state.by_pid

--- Since we are using nix-shell in some places, skip running the shell interpreter
---@type table<string,boolean>
terminal.valid_shell = {
  sh = true,
  zsh = true,
  bash = true,
  csh = true,
  tcsh = true,
  fish = true,
}

local chansend = vim.api.nvim_chan_send
local jobstop = vim.fn.jobstop

function terminal:initialize(cwd, cmd)
  opts = opts or {}
  cwd = cwd or os.getenv("HOME")

  if not path.is_dir(cwd) then
    errorf('Invalid directory provided: %s', cwd)
  end

  self.shell = not cmd
  self.cmd = cmd
  self.id = nil
  self.pid = nil
  self.buffer = nil
  self.cwd = cwd
  self.display_cwd = cwd:gsub(os.getenv("HOME"), "~")
end

---@param s string|string[]?
---@return boolean
function terminal:send(s)
  if self:is_stopped() then
    return false
  elseif not s then
    return true
  end

  s = is.table(s) and table.concat(s, "\n") or s
  s = s .. "\r"
  chansend(self.id, s)

  return true
end

---@param bufnr? integer (default: current buffer)
---@return boolean
function terminal:send_region(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local region = vim.api.nvim_buf_call(bufnr, function() return nvim.region(false) end)
  return self:send(region)
end

---@param bufnr? integer (default: current buffer)
---@return boolean
function terminal:send_buffer(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local str = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
  return self:send(str)
end

---@param bufnr? integer (default: current buffer)
---@return boolean
function terminal:send_current_line(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local line = vim.api.nvim_buf_call(bufnr, function() return vim.fn.getline('.') end)
  return self:send(line)
end

--- Send Ctrl-c
function terminal:send_ctrl_c()
  return self:send('')
end

--- Send Ctrl-Z
function terminal:send_ctrl_z()
  return self:send('')
end

--- Send Ctrl-D
function terminal:send_ctrl_d()
  return self:send('')
end

---@param timeout? integer (default: 500ms)
---@param retries? integer (default: 5)
---@return boolean
function terminal:stop(timeout, retries)
  timeout = timeout or 300
  retries = retries or 5

  if not self:is_running() then
    return false
  end

  local function is_job_stopped(id)
    local status = jobstop(id)
    if status == 0 then
      return true
    else
      return false
    end
  end

  local function wait_for_job_stop(id)
    while not is_job_stopped(id) and retries ~= 0 do
      vim.wait(timeout)
      retries = retries - 1
    end

    return is_job_stopped(id)
  end

  local function stop()
    if not self.id then
      return true
    end

    vim.schedule(function()
      pcall(function()
        local id = self.id
        local cmd = self.cmd
        local buf = self.buffer
        wait_for_job_stop(id, timeout)
        buffer.wipeout(buf)
        self.id = nil
        self.pid = nil
        self.buffer = nil

        if self.shell then
          printf("Stopped terminal for workspace %s", self.display_cwd)
        else
          printf('Stopped terminal [%s] for workspace %s', cmd, self.display_cwd)
        end
      end)
    end)

    if not self.id then
      return true
    end
  end

  vim.wait(timeout, stop)

  while self.id ~= nil or retries ~= 0 do
    vim.wait(timeout, stop)
    retries = retries - 1
  end

  return self.id == nil
end

---@param timeout? integer
---@return integer?
function terminal:get_status_code(timeout)
  timeout = timeout or 0
  if self.id then
    return vim.fn.jobwait({ self.id }, timeout)[1]
  end
end

---Is terminal running?
---@return boolean
function terminal:is_running()
  if not self.id or not self.buffer then
    return false
  else
    return self:get_status_code(0) == -1
  end
end

function terminal:is_stopped()
  return not self:is_running()
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

---Return a nix-shell command depending on whether ./shell.nix | $HOME/shell.nix exists
---@return string?
function terminal:make_nix_cmd()
  local nix_file = self.cwd .. '/shell.nix'
  local is_nix_dir = path.is_file(nix_file)

  if is_nix_dir then
    return sprintf('nix-shell %s', nix_file)
  else
    nix_file = self.cwd .. '/default.nix'
    is_nix_dir = path.is_file(nix_file)
  end

  if is_nix_dir then
    return sprintf('nix-shell %s', nix_file)
  else
    nix_file = os.getenv("HOME") .. '/shell.nix'
    if path.is_file(nix_file) then
      return sprintf('nix-shell %s', nix_file)
    else
      nix_file = os.getenv("HOME") .. '/default.nix'
      if path.is_file(nix_file) then
        return sprintf('nix-shell %s', nix_file)
      end
    end
  end
end

---Make main command to start the terminal with
---@return string
function terminal:make_cmd()
  local cmd = self:make_nix_cmd()
  if not cmd then
    return user_config.shell.cmd
  else
    self.nix_cmd = cmd
    return cmd
  end
end

---Start the terminal job with command obtained by self:make_cmd()
---@return integer?
function terminal:start_job()
  local nix_cmd = self:make_cmd()
  local env = vim.fn.environ()
  env.TERM = "xterm-256color"
  local job_id = vim.fn.jobstart(
    nix_cmd,
    { env = env, cwd = self.cwd, term = true }
  )

  if job_id == 0 or job_id == -1 then
    return
  end

  return job_id
end

---Start terminal and return job id or crash on error
---@return integer?
function terminal:open()
  if self.id and self:is_running() then
    return self.id
  end

  local termbufnr = vim.api.nvim_create_buf(false, true)
  local map = vim.keymap.set
  local id = bufcall(termbufnr, function() return self:start_job() end)

  if not id then
    return
  end

  local pid = vim.fn.jobpid(id)
  local cmd = self.cmd

  map(
    { 'n' }, 'q', ':call HideWindowIfPossible()<CR>',
    { desc = 'Hide buffer', buffer = termbufnr }
  )

  map(
    { 'n' }, 'Q',
    function() self:stop() end,
    { desc = 'Kill terminal and delete buffer', buffer = termbufnr }
  )

  if callable(cmd) then
    local buf = vim.fn.bufnr()
    local filename = buffer.filename(buf)
    local cwd = nvim.get_workspace { buffer = buf }
    cmd = cmd { buf = vim.fn.bufnr(), cwd = cwd, file = filename }
  end

  self.id = id
  self.buffer = termbufnr
  self.pid = pid
  self:send(cmd)

  if cmd then
    printf("Started terminal [%s] in workspace %s", cmd, self.display_cwd)
  else
    printf("Started terminal in workspace %s", self.display_cwd)
  end

  return self.id
end

---@return boolean
function terminal:start()
  if self:is_running() then
    return true
  end

  if not self:open() then
    return false
  end

  by_id[self.id] = self
  by_pid[self.pid] = self

  return true
end

---Is the terminal buffer visible?
---@return boolean
function terminal:is_visible()
  if not self:is_running() then
    return false
  elseif not self.buffer then
    return false
  else
    return buffer.is_visible(self.buffer)
  end
end

---@param direction? string (default: s)
---@param resize? integer (default: -5)
---@return boolean
function terminal:split(direction, resize)
  resize = resize or -5
  if not self:is_running() or not self.buffer then
    return false
  elseif self:is_visible() then
    return true
  elseif self.buffer then
    buffer.split(vim.fn.bufnr(), direction)
    vim.cmd('b ' .. self.buffer)

    if resize then
      buffer.resize(self.buffer, direction, resize)
    end

    return true
  else
    return false
  end
end

---Display terminal window on the right
---@param resize string|integer?
function terminal:split_right(resize)
  return self:split('v', resize)
end

---Display terminal window below
---@param resize string|integer?
function terminal:split_below(resize)
  return self:split('s', resize)
end

---Hide terminal window
function terminal:hide()
  if self.buffer and self:is_visible() then
    bufcall(self.buffer, function()
      vim.cmd ':call HideWindowIfPossible()'
    end)
    return true
  else
    return false
  end
end

function terminal:cd_cwd(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not self:is_running() then
    return false
  else
    self:send('cd ' .. buffer.get_dirname(bufnr))
  end
end

terminal.show = terminal.split

if not user_config.state.autocmd.by_name.stop_terminals_on_exit then
  autocmd(
    { "VimLeave" },
    function(_)
      for _, term in pairs(user_config.state.terminal.by_id or {}) do
        if term:is_running() then
          term:stop()
        end
        if term.buffer and buffer.exists(term.buffer) then
          buffer.wipeout(term.buffer)
        end
      end
    end,
    {
      desc = "Stop all terminals at exit",
      pattern = "*",
      name = "stop_terminals_on_exit",
    }
  )
end

return terminal
