require "nvim-utils.Terminal"

if not REPL then
  REPL = class("REPL", { "set_mappings", "main" })
  REPL:include(Terminal)
  REPL.stop_all = nil
end

function REPL.stop_all()
  list.each(values(user.repls), function(x)
    x:delete()
  end)
end

function REPL.exists(self, tp)
  assert_is_a(self, union("REPL", "string", "number"))

  if is_string(self) then
    return user.repls[self.name]
  elseif is_number(self) then
    if tp == "dir" then
      return user.repls[Path.dirname(Buffer.get_name(self))]
    elseif tp == "workspace" then
      return user.repls[Filetype.workspace(self)]
    else
      return user.repls[Buffer.get_name(self)]
    end
  elseif REPL.is_a(self) then
    return self
  end
end

function REPL:init_shell(opts)
  if user.repls.shell then
    return user.repls.shell
  end

  user.repls.shell = Terminal.init(self, "/bin/bash", opts)
  self.name = "bash"
  self.type = "shell"
  self.set_mappings = nil
  self.main = nil

  return user.repls.shell
end

function REPL:init(bufnr, opts)
  local already = user.repls[bufnr]
  if already and already:is_running() then
    return already
  end

  opts = opts or {}

  if opts.shell then
    return self:init_shell(opts)
  end

  bufnr = bufnr or Buffer.current()

  if not Buffer.exists(bufnr) then
    return false, "invalid buffer: " .. bufnr
  end

  local given_type = opts.workspace and "workspace" or opts.buffer and "buffer" or "dir"
  local exists = REPL.exists(bufnr, given_type)

  if exists then
    return exists
  end

  local ft = Buffer.filetype(bufnr)
  if #ft == 0 and not opts.shell then
    return
  end

  self._bufnr = bufnr
  local ftobj = Filetype(ft):require()
  if not ftobj then
    return false, "no command found for filetype: " .. ftobj
  end

  local replcmd, _opts = ftobj:command(bufnr, "repl")
  local isws = opts.workspace
  local isdir = opts.dir
  local isbuf = opts.buffer

  if _opts then
    dict.merge(opts, { _opts })
  end

  self.filetype = ft
  self.type = isdir and "dir" or isbuf and "buffer" or isws and "workspace"

  local cmd
  if isws then
    if not replcmd.workspace then
      tostderr "repl: no command found for workspace"
      return
    end

    cmd = replcmd.workspace
  elseif isdir then
    if not replcmd.dir then
      tostderr "repl: no command found for current dir"
      return
    end

    cmd = replcmd.dir
  elseif replcmd then
    if not replcmd.buffer then
      tostderr "repl: no command found for buffer"
      return
    end

    cmd = replcmd.buffer
  else
    return false, "no command found"
  end

  if is_table(cmd) then
    self.src = cmd[2]
    cmd = cmd[1]
  end

  self.name = self.src
  user.repls[self.name] = self
  self.set_mappings = nil
  self.main = nil
  self.type = given_type

  if isbuf then
    dict.set(user.buffers, { bufnr, "repls", self.name }, self)
    Autocmd.buffer(bufnr, { "BufDelete" }, {
      callback = function(au)
        self:delete()
      end,
    })
  end

  return Terminal.init(self, cmd, opts)
end

function REPL.main()
  REPL.set_mappings()
end

function REPL.set_mappings()
  local function start(tp)
    local key, desc
    if tp == "buffer" then
      key = "<localleader>rr"
      desc = "start buffer"
    elseif tp == "workspace" then
      key = "<leader>rr"
      desc = "start workspace"
    elseif tp == "shell" then
      key = "<leader>xx"
      desc = "start shell"
    else
      key = "<leader>rR"
      desc = "start dir"
    end

    Kbd.map("n", key, function()
      local buf = Buffer.bufnr()
      local self = REPL(buf, { [tp] = true })

      if not self then
        return
      end

      self:start()

      if self:is_running() then
        print("started REPL for " .. tp .. " with cmd: " .. self.cmd)
      else
        tostderr("could not start REPL for " .. tp .. " with cmd: " .. self.cmd)
      end
    end, desc)
  end

  local function mkkeys(action, tp, ks)
    local key, desc
    if tp == "buffer" then
      key = "<localleader>r"
      desc = action .. " buffer"
    elseif tp == "workspace" then
      key = "<leader>r"
      desc = action .. " workspace"
    elseif tp == "shell" then
      key = "<leader>x"
      desc = action .. " shell"
    else
      key = "<leader>r"
      desc = action .. " dir"
    end

    local mode = "n"
    if is_table(ks) then
      mode, ks = unpack(ks)
    end

    if tp ~= "dir" then
      return mode, key .. ks, desc
    else
      return mode, key .. string.upper(ks), desc
    end
  end

  local function map(name, tp, key, callback)
    local mode, key, desc = mkkeys(name, tp, key)

    Kbd.map(mode, key, function()
      local buf = Buffer.current()
      local self = REPL(buf, { [tp] = true })
      if self then
        callback(self)
      end
    end, { noremap = true, silent = true, desc = desc })
  end

  local function stop(tp)
    map("stop", tp, "q", function(self)
      self:stop()
    end)
  end

  local function dock(tp)
    map("dock", tp, "d", function(self)
      self:dock()
    end)
  end

  local function float(tp)
    map("float", tp, "f", function(self)
      self:center_float()
    end)
  end

  local function _split(tp)
    map("split", tp, "s", function(self)
      self:split()
    end)
  end

  local function vsplit(tp)
    map("vsplit", tp, "v", function(self)
      self:vsplit()
    end)
  end

  local function send_visual_range(tp)
    map("send range", tp, { "v", "e" }, function(self)
      self:send_range()
    end)
  end

  local function send_buffer(tp)
    map("send buffer", tp, "b", function(self)
      self:send_buffer()
    end)
  end

  local function send_current_line(tp)
    map("send line", tp, "e", function(self)
      self:send_current_line()
    end)
  end

  local function send_till_cursor(tp)
    map("send till cursor", tp, "m", function(self)
      self:send_till_cursor()
    end)
  end

  list.each({ "buffer", "workspace", "dir", "shell" }, function(x)
    start(x)
    stop(x)
    _split(x)
    vsplit(x)
    send_till_cursor(x)
    send_visual_range(x)
    send_buffer(x)
    send_current_line(x)
    float(x)
    dock(x)
  end)
end

function REPL:delete()
  if not self:is_running() then
    return
  end

  Terminal.delete(self)
  user.repls[self.name] = nil

  return self
end


