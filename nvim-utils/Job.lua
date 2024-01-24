require "nvim-utils.state"

local jobs = {
  start = vim.fn.jobstart,
  stop = vim.fn.jobstop,
  close = vim.fn.chanclose,
  getpid = vim.fn.jobpid,
  send = vim.fn.chansend,
}

Job = class("Job", { "shell", "format_buffer" })

function Job:opts(opts)
  return {
    clear_env = self.clear_env,
    cwd = self.cwd,
    detach = self.detach,
    env = self.env,
    height = self.height,
    on_exit = self.on_exit,
    on_stdout = self.on_stdout,
    on_stderr = self.on_stderr,
    overlapped = self.overlapped,
    pty = self.pty,
    rpc = self.rpc,
    stderr_buffered = self.stderr_buffered,
    stdout_buffered = self.stdout_buffered,
    stdin = self.stdin,
    width = self.width,
  }
end

function Job:_create_output_handlers()
  local opts = self
  local on_stdout = self.on_stdout
  local on_stderr = self.on_stderr

  local function collect(job_id, data, event)
    list.extend(self.output[event], { data })

    if event == "stdout" and on_stdout then
      on_stdout(job_id, data, event)
    elseif event == "stderr" and on_stderr then
      on_stderr(job_id, data, event)
    end
  end

  self.on_stderr = vim.schedule_wrap(collect)
  self.on_stdout = vim.schedule_wrap(collect)
end

function Job:_create_on_exit_handler()
  local show = self.show
  local output = self.output
  local stdout = output and output.stdout
  local stderr = output and output.stderr
  local on_exit = self.on_exit

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
      if stdout[1] == "" then
        table.remove(stdout, 1)
      end

      if list.last(stdout) == "" then
        list.pop(stdout)
      end

      Buffer.set(outbuf, { 0, -1 }, list.extend({ "-- STDOUT --" }, { stdout, { "-- END OF STDOUT --" } }))
    end

    if lines.stderr then
      if stderr[1] == "" then
        table.remove(stderr, 1)
      end

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

  self.on_exit = vim.schedule_wrap(function(id, exit_status)
    self.exit_status = exit_status

    if output and show then
      show_output()
    end

    if on_exit then
      on_exit(copy(self))
    end

    if after then
      after()
    end

    self.job_id = nil
  end)
end

function Job:getpid()
  if not self.job_id then
    return false
  end

  return getpid(jobs.getpid(self.job_id))
end

function Job:is_active()
  if not self.job_id then
    return false
  elseif self.stopped then
    return false
  end

  return getpid(self:getpid()) and self
end

function Job:close()
  if not self.job_id then
    return
  end

  jobs.close(self.job_id)
  self.job_id = nil

  return self
end

Job.stop = Job.close

---@diagnostic disable-next-line: duplicate-set-field
function Job:send(s)
  assert_is_a[union("string", "table")](s)

  if not self:is_active() then
    return false
  end

  s = is_table(s) and join(s, "\n") or s
  return jobs.send(self.job_id, s)
end

Job.is_running = Job.is_active

function Job.format_buffer(bufnr, cmd, opts)
  if not Buffer.exists(bufnr) then
    return
  end

  local name = Buffer.get_name(bufnr)
  local default = {
    output = true,
    on_exit = function(job)
      local stdout, stderr = job.output.stdout, job.output.stderr
      local has_elems = function(x)
        return is_table(x) and not (#x == 1 and x[1] == "")
      end

      if job.exit_status ~= 0 then
        if has_elems(stderr) then
          tostderr(join(stderr, "\n"))
        else
          tostderr("failed to format buffer: " .. name)
        end

        return
      end

      if has_elems(stdout) then
        Buffer.set_option(bufnr, "modifiable", true)
        Buffer.set(bufnr, { 0, -1 }, stdout)
      elseif has_elems(stderr) then
        Buffer.set_option(bufnr, "modifiable", true)
        tostderr("failed to format buffer: " .. name)
        return
      end
    end,
  }

  opts = dict.lmerge2(default, opts)
  local j = Job(cmd, opts)
  j.target_buffer = bufnr
  j.target_buffer_name = name

  if not j then
    return
  end

  j:start()

  return j
end

function Job:init(cmd, opts)
  opts = opts or {}

  params {
    command = { union("string", "table"), cmd },
    opts = { "table", opts },
  }

  dict.merge2(self, opts)

  self.cmd = cmd
  self.output = (opts.show or opts.output) and { stdout = {}, stderr = {}, buffer = false }

  return self
end

function Job:start()
  if self:is_running() then
    return self
  end

  self:_create_on_exit_handler()

  if self.show or self.output then
    self:_create_output_handlers()
  end

  if before then
    before()
  end

  local handle = jobs.start(self.cmd, self:opts())

  if not handle then
    error("could not run command: " .. dump(cmd))
  end

  self.job_id = handle
  user.jobs[self.job_id] = self

  return self
end
