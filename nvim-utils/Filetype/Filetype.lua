require "nvim-utils.Autocmd"
require "nvim-utils.Job"
require "nvim-utils.Buffer"
require "nvim-utils.Buffer.Win"
require "nvim-utils.Kbd"

if not Filetype then
  Filetype = class("Filetype", {
    main = true,
    lsp = true,
    workspace = true,
    setup_lsp_all = true,
    list = true,
  })

  user.filetypes = {}
  Filetype.lsp = namespace()
end

--- @alias Filetype.commandspec string|table|fun(path:string): string
--- @alias Filetype.mapping table<string,list>
--- @alias Filetype.autocmd table<string,fun(table)>

--- @class filetype
--- @field filetypes table<string,filetype>
--- @field on table see `:help vim.filetype`
--- @field linters string|string[]|Filetype.linters[] or a combination of any
--- @field server Filetype.server
--- @field formatter Filetype.formatter
--- @field compile Filetype.command
--- @field build Filetype.command
--- @field test Filetype.command
--- @field mappings Filetype.mapping
--- @field autocmds Filetype.autocmd
--- @field bo table<string,any> buffer options
--- @field wo table<string,any> window options
--- @field repl table
--- @field jobs table<string,job> jobs for this filetype
--- @field lsp table<string,function> lsp utils
--- @overload fun(string): filetype

--- @class Filetype.command
--- @field buffer Filetype.commandspec
--- @field workspace Filetype.commandspec
--- @field dir Filetype.commandspec

--- @class Filetype.formatter : Filetype.command
--- @field stdin boolean
--- @field append_filename boolean

--- @class Filetype.repl : Filetype.command
--- @field on_input fun(lines:string[]): string[]
--- @field load_from_path fun(path:string, mkfile:fun(p: string))

--- @class Filetype.linters
--- @field config table linter config

--- @class Filetype.server
--- @field config table lsp server config

function Filetype:init(name)
  if Filetype.is_a(name) then
    return name
  elseif is_table(name) then
    assert(name.name, "name is missing in " .. dump(name))
    local l = Filetype(name.name)
    dict.merge(l, { name })

    user.filetypes[name.name] = l
    return l
  elseif is_number(name) then
    assert(Buffer.exists(name), "invalid buffer " .. name)
    return Filetype(Buffer.filetype(name))
  else
    local l = user.filetypes[name]
    if l then
      return l
    end
  end

  self.setup_lsp_all = nil
  self.main = nil
  self.workspace = nil
  self.job = nil
  self.list = nil
  self.jobs = {}
  self.name = name
  user.filetypes[name] = self

  return self
end

function Filetype:setbo(bo)
  bo = bo or self.bo
  if not bo or size(bo) == 0 then
    return
  end

  self:autocmd(function(opts)
    Buffer.set_options(opts.buf, bo)
  end)
end

function Filetype:setwo(wo)
  wo = wo or self.wo
  if not wo or size(wo) == 0 then
    return
  end

  asserttype(wo, "table")

  self:autocmd(function(opts)
    local winnr = Buffer.winnr(opts.buf)
    if winnr then
      Win.set_options(winnr, wo)
    end
  end)
end

local function capitalize(name)
  local first = substr(name, 1, 1)
  return first:upper() .. substr(name, 2, -1)
end

function Filetype:vimcommand(name, callback, opts)
  opts = opts or {}
  local createcmd = vim.api.nvim_buf_create_user_command
  name = "Filetype" .. capitalize(self.name) .. capitalize(name)

  return self:autocmd(function(bufopts)
    createcmd(bufopts.buf, name, callback, opts)
  end, opts)
end

--- @param specs? string|{ [1]: string, config: table }
function Filetype:setup_lsp(specs)
  specs = specs or self.server
  specs = is_string(specs) and { specs } --[[@as table]]
    or specs

  if not specs then
    return
  end

  lsp.setup_server(specs[1], specs.config)

  return self
end

function Filetype:query(attrib, f)
  self = Filetype(self)

  if self[attrib] then
    return f and f(self[attrib]) or self[attrib]
  end
end

function Filetype:command(bufnr, action)
  action = action or "compile"
  local validactions = { "compile", "build", "test", "repl", "formatter" }

  params {
    buffer = { "number", bufnr },
    action = {
      function(x)
        return list.contains(validactions, x)
      end,
      action,
    },
  }

  assert(Buffer.exists(bufnr), "invalid buffer: " .. dump(bufnr))

  local bufname = Buffer.get_name(bufnr)
  local compile = self[action]
  local spec = union("string", "table", "function")

  if not compile then
    return
  else
    assert(is_a[spec](compile))
  end

  if not is_table(compile) then
    compile = { buffer = compile }
  end

  compile = dict.merge(compile, { opts })

  local opts = dict.filter(compile, function(key, _)
    return key ~= "buffer" and key ~= "workspace" and key ~= "dir"
  end)

  params {
    compile = {
      {
        __extra = true,
        ["1?"] = spec,
        ["buffer?"] = spec,
        ["workspace?"] = spec,
        ["dir?"] = spec,
      },
      compile,
    },
  }

  local function getfromtable(X, what)
    for key, value in pairs(X) do
      if what:match(key) then
        return value
      end
    end
  end

  local function dwim(X, what)
    if is_function(X) then
      return X(what)
    elseif is_string(X) then
      return X
    elseif is_string(X[1]) then
      X = copy(X)
      local cmd = X[1]
      X[1] = nil

      return cmd, X
    else
      local out = getfromtable(X, what)
      return dwim(out, what)
    end
  end

  local out = {}
  local function withpath(cmd, p)
    local templ = template(cmd, { path = p })
    if templ then
      return { templ, p }
    else
      return { cmd, p }
    end

    return cmd
  end

  if compile[1] or compile.buffer then
    local cmd, _opts = dwim(compile[1] or compile.buffer, bufname)
    _opts = _opts or {}

    dict.lmerge(_opts, { opts })

    if cmd then
      out.buffer = withpath(cmd, bufname)
    end
  end

  if compile.dir then
    local d = Path.dirname(bufname)
    local cmd, _opts = dwim(compile.dir, d)
    _opts = _opts or {}

    dict.lmerge(_opts, { opts })

    if cmd then
      out.dir = withpath(cmd, d)
    end
  end

  if compile.workspace then
    local ws = Filetype.workspace(bufnr)
    if ws then
      local cmd, _opts = dwim(compile.workspace, ws)
      _opts = _opts or {}

      dict.lmerge(_opts, { opts })

      if cmd then
        out.workspace = withpath(cmd, ws)
      end
    end
  end

  if size(out) == 0 then
    error(self.name .. "." .. action .. ": no commands exist")
  end

  return out, opts
end

function Filetype:format(bufnr, opts)
  opts = opts or {}
  local cmd, _opts = self:command(bufnr, "formatter")

  if not cmd then
    local msg = self.name .. ".formatter: no command exists"
    return nil, msg
  end

  local target
  opts = dict.lmerge(copy(opts), { _opts })
  local stdin = opts.stdin
  local bufname = Buffer.get_name(bufnr)
  local name

  if opts.dir then
    name = "filetype.formatter.dir."
  elseif opts.workspace then
    name = "filetype.formatter.workspace."
  else
    name = "filetype.formatter.buffer."
  end

  if opts.workspace then
    cmd, target = unpack(cmd.workspace)
  elseif opts.buffer or not opts.dir then
    cmd, target = unpack(cmd.buffer)
    if opts.stdin then
      cmd = sprintf("cat %s | %s", target, cmd)
    end
  elseif opts.dir then
    cmd, target = unpack(cmd.dir)
  end

  if target then
    name = name .. target
  else
    name = name .. bufname
  end

  assert(cmd, "filetype." .. self.name .. ".formatter" .. ": no command exists")

  local winnr = Buffer.winnr(bufnr)
  local view = winnr and Win.saveview(winnr)
  opts.args = {}

  local proc = Job.format_buffer(bufnr, cmd, {
    cwd = defined(Path.is_dir(target) and target or nil),
  })

  if proc then
    self.jobs[name] = proc
    return proc
  end
end

function Filetype:format_dir(bufnr, opts)
  opts = opts or {}
  opts.dir = true
  return self:format(bufnr, opts)
end

function Filetype:format_workspace(bufnr, opts)
  opts = opts or {}
  opts.workspace = true
  return self:format(bufnr, opts)
end

function Filetype:require()
  local config = requirem("core.filetype." .. self.name)
  if config then
    return dict.merge(self, { config })
  end
end

function Filetype:loadfile()
  local config = req2path("core.filetype." .. self.name)
  if config then
    local ok, msg = pcall(loadfile, config)

    if ok then
      msg = msg()

      if is_table(msg) then
        return dict.merge(self, { msg })
      else
        return false
      end
    else
      return false, msg
    end
  end
end

function Filetype:map(mode, ks, callback, opts)
  opts = opts or {}
  opts.event = "FileType"
  opts.pattern = self.name
  opts.name = defined(opts.name and self.name .. "." .. opts.name)

  return Kbd.map(mode, ks, callback, opts)
end

function Filetype:autocmd(callback, opts)
  opts = opts or {}
  opts.pattern = self.name
  opts.callback = callback
  opts.name = defined(opts.name and self.name .. "." .. opts.name)

  return Autocmd("FileType", opts)
end

function Filetype:action(bufnr, action, opts)
  if not Buffer.exists(bufnr) then
    return
  end

  action = action or "compile"
  local config = self[action]
  opts = opts or {}
  local ws = opts.workspace
  local isdir = opts.dir
  local tp = opts.workspace and "workspace" or opts.dir and "dir" or "buffer"

  if not config then
    return
  end

  local name = self.name .. "." .. action .. "." .. tp .. "."
  local cmd = self:command(bufnr, action)

  if not cmd then
    return
  end

  local target

  if (ws and not cmd.workspace) or (isdir and not cmd.dir) then
    return
  elseif ws then
    cmd, target = unpack(cmd.workspace)
  elseif isdir then
    cmd, target = unpack(cmd.dir)
  else
    cmd, target = unpack(cmd.buffer)
  end

  name = name .. target
  cmd = is_table(cmd) and join(cmd, " ") or cmd

  local term = Job(cmd, {
    before = function()
      Buffer.save(bufnr)
    end,
    output = true,
    show = ':botright split | resize 10 | b {buf}',
  })

  local ok = term:start()

  if ok then
    self.jobs[name] = term
    return term
  end
end

function Filetype:setup_triggers()
  if self.on then
    vim.Filetype.add(self.on)
    return true
  end
end

function Filetype:setup(should_loadfile)
  if should_loadfile then
    self:loadfile()
  else
    self:require()
  end

  self:setup_triggers()
  self:set_autocmds()
  self:setbo()
  self:setwo()

  vim.schedule(function()
    self:set_mappings()

    self:map("n", "<leader>ct", function()
      self:action(Buffer.bufnr(), "test", { workspace = true })
    end, { desc = "test buffer" })

    self:map("n", "<leader>ct", function()
      self:action(Buffer.bufnr(), "test")
    end, { desc = "test workspace" })

    self:map("n", "<leader>cb", function()
      self:action(Buffer.bufnr(), "build", { workspace = true })
    end, { desc = "build buffer" })

    self:map("n", "<leader>cB", function()
      self:action(Buffer.bufnr(), "build")
    end, { desc = "build workspace" })

    self:map("n", "<leader>cC", function()
      self:action(Buffer.bufnr(), "compile", { workspace = true })
    end, { desc = "compile workspace" })

    self:map("n", "<leader>cc", function()
      self:action(Buffer.bufnr(), "compile")
    end, { desc = "compile buffer" })
  end)

  return self
end

function Filetype.list()
  local builtin_path = Path.join(vim.fn.stdpath "config", "lua", "core", "filetype")
  local user_path = Path.join(os.getenv "HOME", ".nvim", "lua", "user", "filetype")
  local builtin = Path.ls(builtin_path)
  local userconfig = Path.is_dir(user_path) and Path.ls(user_path) or {}
  builtin = list.filter(builtin, function(x)
    return x:match "%.lua$"
  end)
  userconfig = list.filter(userconfig, function(x)
    return x:match "%.lua$"
  end)

  return list.map(list.union(builtin, userconfig), function(x)
    return (Path.basename(x):gsub("%.lua$", ""))
  end)
end

function Filetype.setup_lsp_all()
  local configured = Filetype.list()
  list.each(configured, function(x)
    Filetype(x):setup_lsp()
  end)
end

function Filetype:set_autocmds()
  if not (self.autocmds and size(self.autocmds) > 0) then
    return
  end

  dict.each(self.autocmds, function(name, opts)
    assert_is_a(opts, union("function", "table"))

    local cb, options
    options = {}
    if is_table(opts) then
      cb, options = unpack(opts)
    else
      cb = opts
    end

    options.name = name
    self:autocmd(cb, options)
  end)
end

function Filetype:set_mappings()
  if not (self.mappings and size(self.mappings) > 0) then
    return
  end

  local opts = self.mappings.opts or {}
  local mode = opts.mode or "n"

  dict.each(self.mappings, function(name, spec)
    if name == "opts" then
      return
    end

    assert(#spec >= 3, "expected at least 3 arguments")

    if #spec ~= 4 then
      list.lappend(spec, mode)
    end

    spec[4] = spec[4] or {}
    spec[4] = is_string(spec[4]) and { desc = spec[4] } or spec[4]
    spec[4].name = name

    dict.merge(spec[4], { opts })

    self:map(unpack(spec))
  end)
end

function Filetype.main(use_loadfile)
  local configured = Filetype.list()

  list.each(configured, function(x)
    local obj = Filetype(x)
    obj:setup(use_loadfile)
  end)

  vim.defer_fn(function()
    Kbd.map("n", "<leader>mb", function()
      local buf = Buffer.current()
      Filetype(buf):action(buf, "build", { workspace = true })
    end, "build workspace")

    Kbd.map("n", "<leader>cb", function()
      local buf = Buffer.current()
      Filetype(buf):action(buf, "build", { buffer = true })
    end, "build buffer")

    Kbd.map("n", "<leader>cB", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "build", { dir = true })
      end
    end, "build dir")

    Kbd.map("n", "<leader>mt", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "test", { workspace = true })
      end
    end, "test workspace")

    Kbd.map("n", "<leader>ct", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "test", { buffer = true })
      end
    end, "test buffer")

    Kbd.map("n", "<leader>cT", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "test", { dir = true })
      end
    end, "test dir")

    Kbd.map("n", "<leader>mc", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "compile", { workspace = true })
      end
    end, "compile workspace")

    Kbd.map("n", "<leader>cc", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "compile", { buffer = true })
      end
    end, "compile buffer")

    Kbd.map("n", "<leader>cC", function()
      local buf = Buffer.current()
      local ft = Filetype(buf):require()
      if ft then
        ft:action(buf, "compile", { dir = true })
      end
    end, "compile dir")

    Kbd.map("n", "<leader>mf", function()
      local buf = Buffer.current()
      local ft = Filetype(buf)
      if ft then
        ft:format_workspace(buf)
      end
    end, "format workspace")

    Kbd.map("n", "<leader>bf", function()
      local buf = Buffer.current()
      local ft = Filetype(buf)
      if ft then
        ft:format(buf, { buffer = true })
      end
    end, "format buffer")

    Kbd.map("n", "<leader>bF", function()
      local buf = Buffer.current()
      local ft = Filetype(buf)
      if ft then
        ft:format_dir(buf)
      end
    end, "format dir")
  end, 50)
end
