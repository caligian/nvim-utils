require "nvim-utils.Autocmd"
require "nvim-utils.Async"
require "nvim-utils.Buffer.Buffer"
require "nvim-utils.Kbd"
local lsp = require "nvim-utils.lsp"

Filetype = class("Filetype", {
  static = {
    "setup_lsp_all",
    "from_dict",
    "load_configs",
    "jobs",
    "list",
    "main",
    "list_configs",
    "_resolve",
    "get_workspace",
    "_find_workspace",
    "_get_command",
    "_get_command_and_opts",
  },
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
      ---@diagnostic disable-next-line: need-check-nil
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
  return list.map(Path.ls(user.config_dir .. "/lua/core/ft"), get_name)
end

function Filetype.load_configs()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):load_config()
  end)
end

--------------------------------------------------
local function create_command(spec)
  if is_string(spec) then
    return { buffer = spec }
  else
    return spec
  end
end

--------------------------------------------------
--[[
-- Same case for workspace and dir
-- form1:
{
  buffer = {
    --- such tables can be nested
    [function (x) return x:match 'nvim' end] = function (x) return 'luajit ' .. x end,
    [os.getenv('HOME')] = 'luajit'
  },
}

-- form2:
{
  buffer = 'luajit'
}
--]]

local match_command = ns()

function match_command:match_path(spec, path)
  local function add_path(s)
    return template(s, { path = path })
  end

  local function process(value)
    if is_string(value) then
      return add_path(value)
    elseif is_method(value) then
      local cmd, _ = value(path)
      if cmd then
        return add_path(cmd)
      end
    elseif is_table(value) then
      for key_1, value_1 in pairs(value) do
        local ok = (is_string(key_1) and path:match(key_1)) or (is_method(key_1) and key_1(path))

        if ok then
          return process(value_1)
        end
      end
    end
  end

  return process(spec)
end

function match_command:match(bufnr, spec, cmd_for)
  local ok, msg = is_number(bufnr)
  if ok then
    ok, msg = Buffer.exists(bufnr)
  end
  if not ok then
    error(msg)
  end

  local bufname = Buffer.get_name(bufnr)
  local path
  if not (cmd_for == "workspace" or cmd_for == "buffer" or cmd_for == "dir") then
    error("expected any of workspace, dir, buffer, got " .. dump(cmd_for))
  elseif cmd_for == "workspace" then
    path = Filetype.get_workspace(bufnr, spec.root_dir, 4)
    if not path then
      error("not in workspace: " .. bufname)
    end
  elseif cmd_for == "dir" then
    path = Path.dirname(bufname)
  else
    path = bufname
  end

  local ok = self:match_path(spec[cmd_for], path)
  if not ok then
    error("could not get any command for " .. path)
  end
  local opts = dict.filter(spec, function(key, _)
    return not (key == "buffer" or key == "workspace" or key == "dir" or key == "root_dir")
  end)

  return ok, opts, path
end

function match_command:__call(spec)
  local function get_fn(fn_type)
    return function(bufnr)
      return self:match(bufnr, spec, fn_type)
    end
  end

  return {
    buffer = get_fn "buffer",
    workspace = get_fn "workspace",
    dir = get_fn "dir",
  }
end

function Filetype:get_command(bufnr, cmd_type, cmd_for)
  assert(is_string(cmd_type))
  assert(is_string(cmd_for))

  local spec = self[cmd_type]
  if not is_table(spec) then
    error("invalid spec given " .. dump(cmd_type))
  end
  local cmd_maker = match_command(spec)
  assert(cmd_maker[cmd_for], "cmd_for should be workspace, dir or buffer")

  return cmd_maker[cmd_for](bufnr)
end

--[[
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
    local msg = 'expected string | {{test, callback}, ...}, got ' .. dump(x)
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
    ["buffer?"] = sig,
    ["workspace?"] = sig,
    ["dir?"] = sig,
  }

  local validators = {
    repl = {
      ["on_input?"] = "function",
      ["load_from_path?"] = "function",
    },
    formatter = {
      ["stdin?"] = "boolean",
    },
  }

  form[common].command(cmd)

  local test = validators[cmd_type]
  if test then
    form[test].command(test)
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

  return dict.filter_unless(spec, function(key, _)
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
--]]

--------------------------------------------------
--- @class Filetype

function Filetype:init(name)
  local already = Filetype._resolve(name)
  if already then
    return already
  end

  local luafile = name .. ".lua"

  self.name = name
  self.config_path = Path.join(user.config_dir, "lua", "core", "ft", luafile)
  self.config_require_path = "core.ft." .. name
  self.enabled = {
    mappings = {},
    autocmds = {},
  }
  self.jobs = {}
  self.trigger = false
  self.mappings = false
  self.autocmds = false
  self.buf_opts = false
  self.augroup = "UserFiletype" .. name:gsub("^[a-z]", string.upper)

  nvim.create.autocmd("FileType", {
    pattern = name,
    callback = function(_)
      pcall(function()
        self:load_config()
      end)
    end,
    desc = "load config for " .. self.name,
  })

  user.filetypes[self.name] = self

  --- @type Filetype
  return self
end

function Filetype:load_config()
  return dict.merge(self, require_ftconfig(self.name) or {})
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

    opts.name = name
    opts.desc = opts.desc or name

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

--function Filetype:get_command(bufnr, cmd_type, cmd_for)
--  if not Buffer.exists(bufnr) then
--    return
--  end

--  ---@diagnostic disable-next-line: param-type-mismatch
--  return Filetype._get_command_and_opts(bufnr, cmd_type, self:query(cmd_type), cmd_for)
--end

function Filetype:format_buffer_dir(bufnr)
  return self:format_buffer(bufnr, "dir")
end

function Filetype:format_buffer_workspace(bufnr)
  return self:format_buffer(bufnr, "workspace")
end

function Filetype:format_buffer(bufnr, cmd_for)
  local cmd, opts = self:get_command(bufnr, "formatter", cmd_for or "buffer")
  if not cmd then
    return
  end
  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. ".formatter." .. cmd_for .. "." .. bufname
  self.jobs[name] = Async.format_buffer(bufnr, cmd, opts)
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
  local cmd, opts, p = self:get_command(bufnr, action, cmd_for)
  if not cmd then
    return
  end

  local bufname = Buffer.get_name(bufnr)
  local name = self.name .. "." .. cmd_for .. "." .. bufname
  opts.split = true
  opts.shell = true

  if cmd_for ~= "buffer" then
    cmd = "cd " .. p .. " && " .. cmd
  end

  local j = Async(cmd, opts)

  Buffer.save(bufnr)
  j:start()

  self.jobs[name] = j
  return j
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
        nvim_command(name, cmd[1], cmd[2])
      end)
    end,
  })
end

function Filetype:setup()
  xpcall(function()
    self:load_config()
    self:set_buf_opts()
    self:set_commands()
    self:set_autocmds()
    self:set_mappings()
  end, function(msg)
    logger:warn(msg .. "\n" .. dump(self:get_attribs()))
  end)
end

Filetype.setup_lsp_all = function()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):load_config():setup_lsp()
  end)
end

Filetype.main = function()
  list.each(Filetype.list_configs(), function(ft)
    Filetype(ft):setup()
  end)
end
