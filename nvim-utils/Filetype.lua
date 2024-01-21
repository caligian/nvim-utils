require "nvim-utils.nvim"
require "nvim-utils.Autocmd"
require "nvim-utils.Job"
require "nvim-utils.Buffer"
require "nvim-utils.Buffer.Win"
require "nvim-utils.Kbd"
local lsp = require "nvim-utils.lsp"

Filetype = class("Filetype", {
  "buffer",
  "from_dict",
  "jobs",
  "list",
  "main",
  "_list_configs",
  "_resolve",
  "get_workspace",
  "_find_workspace",
  "_get_command",
  "_get_command_and_opts",
})

function Filetype._resolve(name)
  assert_is_a(name, union("Filetype", "string", "number"))

  if typeof(name) == "Filetype" then
    return name
  elseif is_number(name) then
    if Buffer.exists(name) then
      name = Buffer.get_option(name, "filetype")
    else
      return
    end
  end

  return user.filetypes[name]
end

function Filetype.query(ft, attrib, f)
  local obj = Filetype._resolve(ft)

  if not obj then
    return "invalid filetype " .. dump(ft)
  end

  obj = dict.get(obj, totable(attrib))

  if not obj then
    return false, string.format("%s: invalid attribute: %s", dump(ft), dump(attrib))
  end

  if f then
    return f(obj)
  end

  return obj
end

function Filetype._find_workspace(start_dir, pats, maxdepth, _depth)
  maxdepth = maxdepth or 5
  _depth = _depth or 0
  pats = totable(pats or "%.git/$")

  if maxdepth == _depth then
    return false
  end

  if not Path.is_dir(start_dir) then
    return false
  end

  local children = Path.ls(start_dir, true)
  for i = 1, #pats do
    local pat = pats[i]
    for j = 1, #children do
      if children[j]:match(pat) then
        return start_dir
      end
    end
  end

  return Filetype._find_workspace(Path.dirname(start_dir), pats, maxdepth, _depth + 1)
end

function Filetype.get_workspace(bufnr, pats, maxdepth, _depth)
  if not Buffer.exists(bufnr) then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local ws = Filetype._find_workspace(Path.dirname(bufname), pats, maxdepth, _depth)
  if ws then
    return ws
  end

  local server = Filetype.query(Buffer.filetype(bufnr), "server")
  if not server then
    return
  end

  local lspconfig = require "lspconfig"
  server = totable(server)
  local config = is_string(server) and lspconfig[server] or lspconfig[server[1]]
  local root_dir_checker = server.get_root_dir or config.document_config.default_config.root_dir or config.get_root_dir

  if root_dir_checker then
    return root_dir_checker(bufname)
  else
    return find_workspace(bufname, pats, maxdepth, _depth)
  end
end

local function get_name(x)
  return Path.basename(x):gsub("%.lua", "")
end

function Filetype.list_configs()
  local core_dir = req2path("core.filetype"):gsub("/%.lua", "")
  local user_dir = req2path "user.filetype"
  local core_files = Path.get_files(core_dir)
  local core_names = list.map(core_files, get_name)

  if user_dir then
    user_dir = user_dir:gsub("/%.lua", "")
    local user_files = Path.get_files(user_dir)
    local user_names = list.map(user_files, get_name)

    return list.union(core_names, user_names)
  end

  return core_names
end

--------------------------------------------------
--- @alias command string | function | ({[1]: any, [2]: function})[]

--- @class Command
--- @field buffer? command
--- @field workspace? command
--- @field dir? command
--- @field root_dir? string[] | string workspace_root_patterns

--- @class REPLCommand : Command
--- @field on_input? function
--- @field load_from_path? function

--- @class FormatCommand : Command
--- @field stdin? boolean

--- @param p string path
--- @param spec Command | command
--- @return {[1]: string, [2]: string}
local function match_command(p, spec)
  --[[
  lookup spec:
  eg: {{is_string, string.upper}, {'^[0-9]+$', tonumber}, ...}

  {<test>, <function>},
  <test> = <function> | <lua pattern>
  --]]

  local lookup_dict = function(x)
    local ok = is_table(x) and list.is_a(x, function(X)
      return #X == 2 and is_callable(X[2])
    end)

    if not ok then
      return false, ("expected {<test>, <callable>}, got " .. dump(x))
    end

    return true
  end

  local switch = case {
    {
      lookup_dict,
      function(obj)
        for i = 1, #obj do
          local test, fun = unpack(obj[i])
          local ok

          if is_string(test) then
            if p:match(test) then
              ok = true
            end
          elseif test(p) then
            ok = true
          end

          if ok then
            return { p, fun(p) }
          end
        end
      end,
    },
    {
      is_function,
      function(f)
        return { p, f(p) }
      end,
    },
    {
      is_string,
      function(s)
        return { p, s }
      end,
    },
  }

  local ok = switch:match(spec)
  if not ok then
    error("invalid command spec " .. dump(spec))
  end

  return ok
end

local function is_command(spec)
  if is_string(spec) then
    return true
  end

  local ok = dict.has_some_keys(spec, { "buffer", "workspace", "dir" })
  if not ok then
    return false, "expected dict to have any of .buffer, .workspace, .dir, got " .. dump(spec)
  end

  return true
end

--- @class get_command_return
--- @field workspace? {[1]: string, [2]: string}
--- @field buffer? {[1]: string, [2]: string}
--- @field dir? {[1]: string, [2]: string}

--- @param bufnr number
--- @param spec Command | command
--- @return get_command_return?, string?
local function get_command(bufnr, spec)
  if not is_command(spec) then
    local msg = [[expected string | {{test, callback}, ...}, got ]] .. dump(x)
    return nil, msg
  elseif is_string(spec) then
    spec = { buffer = spec }
  end

  local res = {}
  if spec.workspace then
    local ws_pat = spec.root_dir
    local ws = Filetype.get_workspace(bufnr, ws_pat, 4)

    if ws then
      res.workspace = match_command(ws, spec.workspace)
    end
  end

  if spec.dir then
    local dirname = Path.dirname(Buffer.get_name(bufnr))

    ---@diagnostic disable-next-line: param-type-mismatch
    res.dir = match_command(dirname, spec.dir)
  end

  if spec.buffer then
    res.buffer = match_command(Buffer.get_name(bufnr), spec.buffer)
  end

  list.each(keys(res), function(k)
    local v = res[k]
    local p, cmd = unpack(v)
    local templ = template(cmd, { path = p })
    res[k] = { p, templ }
  end)

  return res
end

--- @param cmd_type "repl" | "compile" | "build" | "test" | "format"
--- @param cmd command | Command
local function validate(cmd_type, cmd)
  if not strmatch(cmd_type, "repl", "compile", "build", "test", "format") then
    error(dump { "repl", "compile", "build", "test", "format" })
  elseif is_string(cmd) then
    return { buffer = cmd }
  end

  local sig = union("string", "function", "table")

  local common = {
    __extra = true,
    ["buffer?"] = sig,
    ["workspace?"] = sig,
    ["dir?"] = sig,
  }

  local validators = {
    repl = {
      __extra = true,
      ["on_input?"] = "function",
      ["load_from_path?"] = "function",
    },
    formatter = {
      __extra = true,
      ["stdin?"] = "boolean",
    },
  }

  params { command = { common, cmd } }

  local test = validators[cmd_type]
  if test then
    params { command = { test, cmd } }
  end

  assert(is_command(cmd))

  return cmd
end

--- @param bufnr number
--- @param cmd_type "repl" | "compile" | "build" | "test" | "format"
--- @param spec command | Command
--- @param cmd_for string "buffer" | "workspace" | "dir"
--- @return (string|get_command_return)?
function Filetype._get_command(bufnr, cmd_type, spec, cmd_for)
  if not spec then
    return
  end

  validate(cmd_type, spec)

  spec = is_string(spec) and { buffer = spec } or spec

  if cmd_for then
    assert(spec[cmd_for], cmd_for .. ": command does not exist for " .. cmd_type)

    spec = { [cmd_for] = spec[cmd_for] }
    local ok = get_command(bufnr, spec)

    if ok then
      return ok[cmd_for]
    end
  end

  return get_command(bufnr, spec)
end

--- @param spec command | Command
--- @return table?
function Filetype._get_opts(spec)
  if not spec then
    return
  end

  spec = is_string(spec) and { buffer = spec } or spec

  return dict.filter_unless(spec --[[@as table]], function(key, _)
    return strmatch(key, "^buffer$", "^workspace$", "^dir$")
  end)
end

--- @param bufnr number
--- @param cmd_type "repl" | "compile" | "build" | "test" | "format"
--- @param spec command | Command
--- @param cmd_for string "buffer" | "workspace" | "dir"
--- @return (string|get_command_return)?, table?
function Filetype._get_command_and_opts(bufnr, cmd_type, spec, cmd_for)
  if not spec then
    return
  end

  local cmd = Filetype._get_command(bufnr, cmd_type, spec, cmd_for)

  if not cmd then
    return
  end

  local opts = Filetype._get_opts(spec) or {}
  return cmd, opts
end

--------------------------------------------------
--- @class Filetype
Filetype.buffer = namespace "Filetype.buffer"

function Filetype:init(name)
  local already = Filetype._resolve(name)
  if already then
    return already
  end

  local luafile = name .. ".lua"

  self.name = name

  self.requires = {
    config = "core.filetype." .. name,
    user_config = "user.filetype." .. name,
  }

  self.paths = {
    config_path = Path.join(vim.fn.stdpath "config", "lua", "core", "filetype", luafile),
    user_config = Path.join(user.user_dir, "user", "filetype", luafile),
  }

  self.enabled = {
    mappings = {},
    autocmds = {},
  }

  self.jobs = {}
  self.trigger = false
  self.mappings = false
  self.autocmds = false
  self.buf_opts = false
  self.win_opts = false
  self.on = false
  self.augroup = "UserFiletype" .. name:gsub("^[a-z]", string.upper)

  nvim.create.autocmd("FileType", {
    pattern = name,
    callback = function(_)
      self:require()
    end,
  })

  user.filetypes[self.name] = self

  --- @type Filetype
  return self
end

function Filetype.buffer:__call(bufnr)
  if not Buffer.exists(bufnr) then
    return
  end

  local ft = Buffer.filetype(bufnr)
  if #ft == 0 then
    return
  end

  return Filetype(ft)
end

function Filetype:require(use_loadfile)
  local use = use_loadfile and reqloadfilex or requirex
  local core_config = use(self.requires.config) or {}
  local user_config = Path.exists(self.paths.user_config) and use(self.requires.user_config) or {}

  return dict.merge(self, { core_config, user_config })
end

function Filetype:loadfile()
  return self:require(true)
end

function Filetype:map(mode, ks, cb, opts)
  local mapping = Kbd(mode, ks, cb, opts)
  mapping.event = "Filetype"
  mapping.pattern = self.name

  if mapping.name then
    self.enabled.mappings[mapping.name] = mapping
  end

  return mapping:enable()
end

function Filetype:create_autocmd(callback, opts)
  opts = copy(opts or {})
  opts = is_string(opts) and { name = opts } or opts
  opts.pattern = self.name
  opts.group = self.augroup
  opts.callback = function(au_opts)
    pcall_warn(callback, au_opts)
  end
  local name = opts.name
  local au = Autocmd("FileType", opts)

  if name then
    self.enabled.autocmds[name] = au
  end

  return au
end

function Filetype:set_autocmds(mappings)
  mappings = mappings or {}

  dict.each(mappings, function(name, value)
    local fun = value
    local opts = {}

    if is_table(value) then
      fun = value[1]
      opts = value[2] or opts
    end

    self:create_autocmd(fun, opts)
  end)
end

function Filetype:set_mappings(mappings)
  mappings = mappings or self.mappings or {}

  dict.each(mappings, function(key, value)
    value[4] = copy(value[4] or {})
    value[4].event = "Filetype"
    value[4].pattern = self.name
    value[4].name = key
    value[4].desc = value[4].desc or key
    self.enabled.mappings[key] = Kbd.map(unpack(value))
  end)
end

function Filetype:set_buf_opts(buf_opts)
  buf_opts = buf_opts or self.buf_opts

  if not buf_opts then
    return
  end

  self:create_autocmd(function(opts)
    Buffer.set_options(opts.buf, buf_opts)
  end)
end

function Filetype:enable_triggers(trigger)
  trigger = trigger or self.trigger
  if not self.trigger then
    return
  end

  vim.filetype.add(self.trigger)
  return true
end

function Filetype:get_command(bufnr, cmd_type, cmd_for)
  if not Buffer.exists(bufnr) then
    return
  end

  return Filetype._get_command_and_opts(bufnr, cmd_type, self:query(cmd_type), cmd_for)
end

function Filetype:format_buffer_dir(bufnr)
  return self:format_buffer(bufnr, "dir")
end

function Filetype:format_buffer_workspace(bufnr)
  return self:format_buffer(bufnr, "workspace")
end

function Filetype:format_buffer(bufnr, cmd_for)
  local cmd, opts = self:get_command(bufnr, "formatter", cmd_for)

  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname

  cmd = cmd[2]
  self.jobs[name] = Job.format_buffer(bufnr, cmd, opts)
  self.jobs[name]:start()

  return self.jobs[name]
end

function Filetype:compile_buffer_workspace(bufnr, action)
  return self:compile_buffer(bufnr, action, "workspace")
end

function Filetype:compile_buffer_dir(bufnr, action)
  return self:compile_buffer(bufnr, action, "dir")
end

function Filetype:compile_buffer(bufnr, action, cmd_for)
  cmd_for = cmd_for or "workspace"
  local cmd, opts = self:get_command(bufnr, action, cmd_for)
  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname

  if #cmd == 2 then
    cmd = cmd[2]
    opts.show = true
    self.jobs[name] = Job(cmd, opts)

    if self.jobs[name] then
      self.jobs[name]:start()
      return self.jobs[name]
    end
  end
end

function Filetype:setup_lsp(specs)
  specs = specs or self.server
  if not specs then
    return
  end

  specs = is_string(specs) and { specs } or specs
  if not specs then
    return
  end

  lsp.setup_server(specs[1], specs.config)

  return self
end

function Filetype:set_commands(commands)
  commands = commands or self.commands
  if not commands then
    return
  end

  nvim.create.autocmd("FileType", {
    pattern = self.name,
    callback = function(opts)
      dict.each(commands, function(name, cmd)
        cmd[2] = copy(cmd[2] or {})
        cmd[2].buffer = opts.buf
        mkcommand(name, cmd[1], cmd[2])
      end)
    end,
  })
end

function Filetype:setup()
  vim.schedule(function()
    local default_mappings = require "nvim-utils.defaults.Filetype"

    xpcall(function()
      self:require()
      self:set_buf_opts()
      self:set_commands()
      self:set_autocmds()
      self:set_mappings()
      self:setup_lsp()
      Kbd.from_dict(default_mappings)
    end, function()
      logger:warn(dump {
        obj = copy(self),
        buf_opts = self.buf_opts or {},
        mappings = self.mappings or {},
        autocmds = self.autocmds or {},
        commands = self.commands or {},
        lsp = self.server or {},
      })
    end)
  end)
end

function Filetype.main()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):setup()
  end)
end


