-- local utils = require 'nvim-utils.Filetype.utils'
local utils = require "nvim-utils.Filetype.utils"
local mod = {}

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
    local ws = utils.get_workspace(bufnr, ws_pat, 4)

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

    if templ then
      res[k] = { p, templ }
    end
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
function mod.get_command(bufnr, cmd_type, spec, cmd_for)
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
function mod.get_opts(spec)
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
function mod.get_command_and_opts(bufnr, cmd_type, spec, cmd_for)
  if not spec then
    return
  end

  local cmd = mod.get_command(bufnr, cmd_type, spec, cmd_for)

  if not cmd then
    return
  end

  local opts = mod.get_opts(spec) or {}
  return cmd, opts
end

return mod
