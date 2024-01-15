require "nvim-utils.shlex"

local uv = require "luv"

--- @class Job.pipes
--- @field stderr uv_pipe_t
--- @field stdout uv_pipe_t
--- @field stdin uv_pipe_t

--- @class Job.opts
--- @field cwd string
--- @field split string|boolean
--- @field float boolean|table
--- @field before function
--- @field on_exit function
--- @field on_stdout function
--- @field on_stderr function
--- @field after function
--- @field output boolean
--- @field args string[]

--- @class Job.output
--- @field buffer number
--- @field stdout string[]
--- @field stderr string[]

--- @class Job
--- @field cmd string|string[]
--- @field check uv_check_t
--- @field on_stdout function
--- @field on_stderr function
--- @field on_exit function
--- @field after function
--- @field before function
--- @field output Job.output
--- @field handle uv_handle_t
--- @field pipes Job.pipes
--- @field exit_status number
--- @overload fun(cmd:string, opts?:Job.opts): Job
Job = class("Job", { format_buffer = true, shell = true })
dict.get(user, "jobs", true)

function Job:mkpipes()
  self.pipes = {} --[[@as Job.pipes]]
  local stdout, stderr, stdin

  stdout = uv.new_pipe()
  stderr = uv.new_pipe()
  stdin = uv.new_pipe()

  self.pipes.stdout = stdout
  self.pipes.stderr = stderr
  self.pipes.stdin = stdin
end

function Job:opts(opts)
  local remove = {
    "args",
    "on_stdout",
    "on_stderr",
    "on_exit",
    "command_maker",
    "shell",
    "show",
    "output",
    "before",
    "after",
  }

  opts = copy(opts or {})
  list.each(remove, function(x)
    opts[x] = nil
  end)

  opts.stdio = {
    self.pipes.stdin,
    self.pipes.stdout,
    self.pipes.stderr,
  }

  opts.args = self.args

  return opts
end

local function write_cmd(cmd)
  local tempfile = vim.fn.tempname()
  local fh = io.open(tempfile, "w")

  if not fh then
    error("could not write command: " .. cmd)
  end

  fh:write(cmd)
  fh:close()

  return tempfile
end

local function create_cmd(cmd, cmdmaker, shell)
  local path, fullcmd, shell

  if not cmdmaker then
    if shell == "zsh" then
      fullcmd = join({
        "#!/usr/bin/zsh",
        cmd,
      }, "\n")
    else
      fullcmd = join({
        "#!/bin/bash",
        cmd,
      }, "\n")
    end
  else
    fullcmd = cmdmaker(cmd)
  end

  path = write_cmd(fullcmd)

  return path, fullcmd, "bash", { path }
end

function Job:start(opts)
  if self:is_running() then
    return self
  end

  opts = opts or {}

  self:mkpipes()
  self:_create_on_exit_handler(opts)

  if opts.show or opts.output then
    self:_create_output_handlers(opts)
  end

  local cmd, args
  if is_string(self.cmd) then
    local fullcmd, path

    path, fullcmd, cmd, args = create_cmd(self.cmd, opts.command_maker)
    self.shellcmd = fullcmd
    self.cmd_path = path
    self.args = args
  end

  local before = opts.before
  local after = opts.after

  if before then
    before()
  end

  opts = self:opts(opts)

  local function on_exit(...)
    if self.cmd_path then
      Path.delete(self.cmd_path)
    end

    self.on_exit(...)

    if after then
      after(self)
    end
  end

  local handle = uv.spawn(cmd, opts, on_exit)

  if not handle then
    error("could not run command: " .. dump(cmd))
  end

  self.handle = handle
  self.check = uv.new_check()

  self.check:start(vim.schedule_wrap(function()
    if self:is_closing() then
      self:close()
    end
  end))

  if self.on_stderr then
    uv.read_start(self.pipes.stderr, self.on_stderr)
    uv.read_start(self.pipes.stderr, self.on_stderr)
  end

  if self.on_stdout then
    uv.read_start(self.pipes.stdout, self.on_stdout)
  end

  user.jobs[self.handle] = self

  return self
end

function Job:_create_output_handlers(opts)
  local function collect(_, data, handler_type, handler)
    if data then
      data = vim.split(data, "\n")
      list.extend(self.output[handler_type], { data })
    end

    if handler then
      handler(data)
    end
  end

  self.on_stderr = vim.schedule_wrap(function(err, data)
    collect(err, data, "stderr", opts.on_stderr)
  end)

  self.on_stdout = vim.schedule_wrap(function(err, data)
    collect(err, data, "stdout", opts.on_stdout)
  end)
end

function Job:_create_on_exit_handler(opts)
  opts = opts or {}
  local show = opts.show
  local output = defined(show and true, opts.output)
  local stdout = self.output.stdout
  local stderr = self.output.stderr

  local function notempty(x)
    return #x > 0
  end

  local function has_lines()
    return {
      stdout = list.some(stdout, notempty) and true,
      stderr = list.some(stderr, notempty) and true,
    }
  end

  local function create_outbuf()
    local buf = Buffer.scratch()

    Buffer.autocmd(buf, { "WinClosed" }, {
      callback = function()
        Buffer.wipeout(buf)
        self.output.buffer = nil
      end,
    })

    return buf
  end

  local function write_output(outbuf)
    local lines = has_lines()

    if lines.stdout then
      if list.last(stdout) == "" then
        list.pop(stdout)
      end

      Buffer.set(outbuf, { 0, -1 }, list.extend({ "-- STDOUT --" }, { stdout, { "-- END OF STDOUT --" } }))
    end

    if lines.stderr then
      if list.last(stderr) == "" then
        list.pop(stderr)
      end

      Buffer.set(outbuf, { 0, -1 }, list.extend({ "-- STDERR --" }, { stderr, { "-- END OF STDERR --" } }))
    end

    if Buffer.linecount(outbuf) > 0 then
      return outbuf
    end
  end

  local function show_output()
    local buf = write_output(create_outbuf())

    if not buf then
      return
    elseif not show then
      return
    end

    self.output.buffer = buf

    if is_string(show) then
      Buffer.split(buf, show)
    elseif is_table(show) then
      show = copy(show)

      if size(show) == 0 then
        show.center = { 100, 30 }
      end

      Buffer.float(buf, show)
    else
      Buffer.split(buf, "split")
      Buffer.call(buf, function()
        vim.cmd "resize 15"
      end)
    end
  end

  self.on_exit = vim.schedule_wrap(function(exit_status)
    self.exit_status = exit_status
    self:close()

    if output then
      show_output()
    end

    if opts.on_exit then
      opts.on_exit(self)
    end
  end)
end

function Job:init(cmd)
  assert_is_a[union("string", "table")](cmd)

  if is_table(cmd) then
    cmd[1] = whereis(cmd[1])[1]
    assert(cmd and not is_empty(cmd), "invalid executable: " .. dump(cmd))

    self.cmd = cmd[1]
    self.args = list.sub(cmd, 2, -1)
  else
    self.cmd = cmd
    self.args = {}
  end

  self.output = { stdout = {}, stderr = {}, buffer = false }

  return self
end

---@diagnostic disable-next-line: duplicate-set-field
function Job:wait(timeout, tries, inc)
  if self.exit_status then
    return true
  elseif not self.handle or not uv.is_active(self.handle) then
    return false
  end

  timeout = timeout or 50
  tries = tries or 10
  inc = inc or timeout / 5
  local i = 0

  while i <= tries do
    if self.exit_status then
      break
    elseif uv.is_closing(self.handle) then
      break
    elseif self:is_closing "stdout" or self:is_closing "stderr" then
      break
    end

    vim.wait(timeout)

    timeout = timeout + inc
    i = i + 1
    inc = timeout / 10
  end

  return self.exit_status ~= nil
end

function Job:wait_for_output(timeout, tries, inc)
  if self:wait(timeout, tries, inc) then
    return { stdout = self.output.stdout, stderr = self.output.stderr }
  end

  return false
end

function Job:close()
  if not self.handle then
    return
  end

  self.pipes.stdout:shutdown()
  self.pipes.stderr:shutdown()
  self.handle:close()
  self.check:stop()

  user.jobs[self.handle] = nil

  self.handle = nil

  return self
end

Job.stop = Job.close

function Job:is_active()
  if not self.handle then
    return false
  elseif not uv.is_active(self.handle) then
    return false
  end

  return true
end

function Job:is_closing(pipes)
  if not self.handle then
    return false
  elseif pipes == true then
    return self.pipes.stdin and uv.is_closing(self.pipes.stdin),
      self.pipes.stdout and uv.is_closing(self.pipes.stdout),
      self.pipes.stderr and uv.is_closing(self.pipes.stderr)
  elseif pipes == "stdout" then
    return self.pipes.stdout and uv.is_closing(self.pipes.stdout)
  elseif pipes == "stdin" then
    return self.pipes.stdin and uv.is_closing(self.pipes.stdin)
  elseif pipes == "stderr" then
    return self.pipes.stderr and uv.is_closing(self.pipes.stderr)
  else
    return uv.is_closing(self.handle)
  end
end

function Job:close_stderr_pipe()
  if self.pipes.stderr and not uv.is_closing(self.pipes.stderr) then
    self.pipes.stderr:shutdown()
    return true
  end

  return false
end

function Job:close_stdin_pipe()
  if self.pipes.stdin and not uv.is_closing(self.pipes.stdin) then
    self.pipes.stdin:shutdown()
    return true
  end

  return false
end

function Job:close_stdout_pipe()
  if self.pipes.stdout and not uv.is_closing(self.pipes.stdout) then
    self.pipes.stdout:shutdown()
    return true
  end

  return false
end

function Job:close_pipes()
  return Job.close_stdout_pipe(self), Job.close_stderr_pipe(self), Job.close_stdin_pipe(self)
end

---@diagnostic disable-next-line: duplicate-set-field
function Job:send(s)
  assert_is_a[union("string", "table")](s)

  if not self.handle or not uv.is_active(self.handle) then
    return false
  elseif self:is_closing "stdin" then
    return false
  end

  s = is_string(s) and strsplit(s, "\n") or s
  return uv.write(self.pipes.stdin, s)
end

Job.is_running = Job.is_active

function Job.format_buffer(bufnr, cmd, opts)
  if not Buffer.exists(bufnr) then
    return
  end

  local name = Buffer.get_name(bufnr)
  local j = Job(cmd)
  j.target_buffer = bufnr
  j.target_buffer_name = name

  if not j then
    return
  end

  opts = copy(opts)

  Buffer.save(bufnr)

  return j:start(dict.merge({
    output = true,
    on_exit = function(job)
      Buffer.set_option(bufnr, "modifiable", true)

      if job.exit_status ~= 0 then
        if #job.output.stderr > 0 then
          tostderr(join(job.output.stderr, "\n"))
        end
        tostderr("failed to format buffer: " .. name)
      end

      if #job.output.stdout > 0 then
        Buffer.set(bufnr, { 0, -1 }, job.output.stdout)
        vim.cmd "redraw!"
      elseif #job.output.stderr > 0 then
        tostderr("failed to format buffer: " .. name)
      end
    end,
  }, { opts }))
end

function Job.shell(cmd, opts)
  assert_is_a.string(cmd)

  local j = Job(cmd)
  if j then
    return j:start(opts)
  end
end

vim.api.nvim_create_autocmd({ "ExitPre" }, {
  pattern = "*",
  callback = function()
    dict.each(user.jobs, function(_, obj)
      obj:stop()
    end)
  end,
})
