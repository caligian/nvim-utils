local Vimjob = class("VimJob", {
  "buffer",
  "format_buffer",
})

local job = {
  start = vim.fn.jobstart,
  stop = vim.fn.jobstop,
  pid = vim.fn.jobpid,
  resize = vim.fn.jobresize,
  wait = vim.fn.jobwait,
  send = vim.fn.jobsend,
}

function Vimjob:init(cmd, opts)
  params {
    cmd = { union("table", "string"), cmd },
    ["opts?"] = {
      {
        __extra = true,
        ["output?"] = "boolean",
        ["stdout?"] = "boolean",
        ["stderr?"] = "boolean",
        ["buffered?"] = "boolean",
        ["disable_stdin?"] = "boolean",
        ["stdout_buffer?"] = "boolean",
      },
      opts,
    },
  }

  opts = copy(opts or {})
  local collect_output = opts.output
  local collect_stdout = opts.stdout
  local collect_stderr = opts.stderr
  local stdout_buffer = opts.stdout_buffer
  local stderr_buffer = opts.stderr_buffer
  local buffered = opts.buffered
  local show = opts.show
  local disable_stdin = opts.disable_stdin
  local on_stdout = opts.on_stdout
  local _on_exit = opts.on_exit
  local on_stderr = opts.on_stderr

  opts.on_stdout = nil
  opts.on_stderr = nil
  opts.on_exit = nil
  opts.output = nil
  opts.stdout = nil
  opts.stderr = nil
  opts.stdout_buffer = nil
  opts.stderr_buffer = nil
  opts.buffered = nil
  opts.show = nil
  opts.disable_stdin = nil

  if disable_stdin then
    opts.stdin = nil
  end

  if show then
    collect_output = true
  end

  if collect_output then
    stderr_buffer = Buffer.scratch()
    stdout_buffer = Buffer.scratch()
    self.stderr_buffer = stderr_buffer
    self.stdout_buffer = stdout_buffer
  end

  local function output_handler(_, data, event)
    if not data then
      return
    end

    if event == "stdout" then
      if stdout_buffer then
        Buffer.set_lines(stdout_buffer, -1, -1, false, data)
      else
        list.extend(self.stdout, { data })
      end

      if on_stdout then
        on_stdout(self)
      end
    else
      if stderr_buffer then
        Buffer.set_lines(stderr_buffer, -1, -1, false, data)
      else
        list.extend(self.stderr, { data })
      end

      if on_stderr then
        on_stderr(self)
      end
    end
  end

  local function on_exit(_, exit_status, event)
    self.exit_status = exit_status

    local function haslines(lines)
      lines = is_number(lines) and Buffer.lines(lines) or lines
      return list.some(lines, function(x)
        return #x > 0
      end)
    end

    if collect_output then
      local all_output = {}

      if haslines(stdout_buffer or self.stdout) then
        all_output[1] = "-- STDOUT --"

        if is_number(stdout_buffer) then
          list.extend(all_output, { Buffer.lines(stdout_buffer) })
          Buffer.wipeout(stdout_buffer)
        else
          list.extend(all_output, { self.stdout })
        end

        all_output[#all_output] = "-- END OF STDOUT --"
      end

      if haslines(stderr_buffer or self.stderr) then
        all_output[#all_output + 1] = "-- STDERR --"

        if is_number(stderr_buffer) then
          list.extend(all_output, { Buffer.lines(stderr_buffer) })
          Buffer.wipeout(stderr_buffer)
        else
          list.extend(all_output, { self.stderr })
        end

        list.append(all_output, { "-- END OF STDERR --" })
      end

      self.stdout_buffer = nil
      self.stderr_buffer = nil

      if haslines(all_output) then
        self.output = all_output
        local output_buffer = Buffer.scratch()
        self.output_buffer = output_buffer

        Buffer.set_option(output_buffer, "bufhidden", "wipe")
        Buffer.set_keymap(output_buffer, "n", "q", ":hide<CR>", { desc = "hide buffer" })
        Buffer.autocmd(output_buffer, { "BufHidden", "BufDelete", "WinLeave" }, {
          callback = function()
            Buffer.wipeout(output_buffer)
            self.output_buffer = nil
          end,
        })

        show = show == true and "split" or show
        Buffer.set(output_buffer, { 0, -1 }, all_output)

        if is_table(show) then
          Buffer.float(output_buffer, show)
        elseif is_string(show) then
          Buffer.split(output_buffer, show)
        end
      end
    end

    if _on_exit then
      _on_exit(self)
    end
  end

  opts.on_stdout = vim.schedule_wrap(output_handler)
  opts.on_stderr = vim.schedule_wrap(output_handler)
  opts.on_exit = vim.schedule_wrap(on_exit)

  local ok, job_id = pcall(job.start, cmd, opts)
  if not ok then
    return
  elseif job_id == 0 or job_id == -1 then
    return
  end

  self.id = job_id
  self.pid = job.pid(job_id)
  self.stdout = {}
  self.stderr = {}

  return self
end

function Vimjob:is_running()
  if not self.id then
    return
  end

  local ok, _ = pcall(job.pid, self.id)
  return ok
end

function Vimjob:kill()
  if self:is_running() then
    killpid(self.id)
    return true
  end
end

function Vimjob:stop()
  if self:is_running() then
    job.stop(self.id)
    return true
  end
end

function Vimjob:send(s)
  if not self:is_running() then
    return
  end

  vim.fn.chansend(self.id, s)

  return self
end

return Vimjob
