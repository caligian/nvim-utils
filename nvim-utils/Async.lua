uv = vim.loop
Async = class("Async", {})

function Async:create_pipes()
  self.pipes = {
    stdin = uv.new_pipe(),
    stdout = uv.new_pipe(),
    stderr = uv.new_pipe(),
  }
  return self
end

function Async:_read_start()
  self.pipes.stdout:read_start(vim.schedule_wrap(function(_, data)
    if data then
      list.extend(self.output.stdout, strsplit(data, "\n"))
    end
  end))

  self.pipes.stderr:read_start(vim.schedule_wrap(function(_, data)
    if data then
      list.extend(self.output.stderr, strsplit(data, "\n"))
    end
  end))
end

function Async:close_pipes()
  dict.each(self.pipes, function(_, value)
    value:shutdown()
  end)
end

function Async:_check_start()
  self._check = uv.new_check()
  self._check:start(function()
    if self.handle:is_closing() then
      self:close_pipes()
    end
  end)
end

function Async:write(str)
  if not self:is_active() then
    return
  end

  self.pipes.stdin:write(str)
  return self
end

function Async:close_stdin()
  if self.pipes.stdin:is_closing() then
    return
  end

  self.pipes.stdin:shutdown()
  return self
end

function Async:stop()
  if self.handle:is_closing() then
    return
  end

  self.handle:close()
  return self
end

function Async:start(cmd)
  if self:is_active() then
    return self
  end

  local on_exit = self.on_exit
  self.handle = vim.loop.spawn(
    self.cmd,
    self.opts,
    vim.schedule_wrap(function(code, signal)
      self.exit_status = code
      self.exit_signal = signal

      if on_exit then
        on_exit(code, signal, self.output)
      end

      if not self.split or self.float then
        return
      end

      local out = self.output
      local stdout, stderr = out.stdout, out.stderr
      local buf = Buffer.scratch()
      self.output.buffer = buf
      local lines = {}

      if stdout[1] and #stdout[1] == 0 then
        list.shift(stdout)
      end

      if stderr[1] and #stderr[1] == 0 then
        list.shift(stderr)
      end

      if #stdout > 0 then
        list.append(lines, "-- STDOUT --")
        list.extend(lines, stdout)
      end

      if #stderr > 0 then
        list.append(lines, "-- STDERR --")
        list.extend(lines, stderr)
      end

      Buffer.set(buf, { 0, -1 }, lines)

      if self.split then
        Buffer.split(buf, self.split)
      elseif self.float then
        Buffer.float(buf, self.float)
      end
    end)
  )

  if not self.handle then
    return
  end

  self:_read_start()
  self:_check_start()

  return self
end

function Async:is_active()
  if not self.handle then
    return false
  end

  return (not self.handle:is_closing()) and self
end

function Async:kill(signum)
  if not self:is_active() then
    return
  end

  self.handle:kill(signum or 1)
  return self
end

function Async:init(cmd, opts)
  opts = copy(opts or {})
  local on_exit, output, show_split, show_float, args, shell
  args = opts.args
  show_split = opts.split
  show_float = opts.float
  on_exit = opts.on_exit
  output = opts.output
  shell = opts.shell

  if show_split == true then
    show_split = "botright split | b {buf} | resize 10"
  end

  if show_float == true then
    show_float = { center = { 0.8, 0.8 } }
  end

  if show_split or show_float then
    output = true
  end

  if shell then
    assert(is_string(cmd))
    args = { "-c", cmd }
    cmd = "bash"
  elseif is_table(cmd) then
    args = list.sub(cmd, 2, -1)
    cmd = cmd[1]
  else
    args = opts.args
  end

  self.cmd = cmd
  self.handle = false
  self.on_exit = on_exit
  self.output = output and { stdout = {}, stderr = {} }
  self.exit_signal = false
  self.exit_status = false
  self.split = show_split
  self.float = show_float
  self.opts = dict.filter(opts, function(key, _)
    return not (key:match "^on_" or key == "output" or key == "split" or key == "float")
  end)
  self:create_pipes()
  self.opts.stdio = { self.pipes.stdin, self.pipes.stdout, self.pipes.stderr }
  self.opts.args = args

  return self
end

function Async.format_buffer(bufnr, cmd, opts)
  assert(cmd, "no command provided")
  assert_is_a.string(cmd)

  local bufname = Buffer.get_name(bufnr)
  opts = opts or {}
  opts = copy(opts)
  cmd = F(cmd, { path = bufname })
  opts.args = { "-c", cmd }
  cmd = "bash"

  function opts.on_exit(_, _, output)
    Buffer.set_option(bufnr, "modifiable", true)

    local out = output.stdout
    local err = output.stderr

    if #err > 0 then
      tostderr(join(err, "\n"))
      return
    end

    if #out > 0 then
      Buffer.set(bufnr, { 0, -1 }, out)
    end
  end

  opts.output = true

  Buffer.save(bufnr)
  Buffer.set_option(bufnr, "modifiable", false)

  local j = Async(cmd, opts)
  j:start()

  if not j then
    Buffer.set_option(bufnr, "modifiable", true)
  end

  return j
end
