function vimsize()
  local scratch = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_call(scratch, function()
    vim.cmd "tabnew"
    local tabpage = vim.fn.tabpagenr()
    width = vim.fn.winwidth(0)
    height = vim.fn.winheight(0)
    vim.cmd("tabclose " .. tabpage)
  end)

  vim.cmd(":bwipeout! " .. scratch)

  return { width, height }
end

function tostderr(...)
  for _, s in ipairs { ... } do
    vim.api.nvim_err_writeln(s)
  end
end

function nvimexec(s, as_string)
  local ok, res = pcall(vim.api.nvim_exec2, s, { output = true })
  if ok and res and res.output then
    return not as_string and strsplit(res.output, "\n") or res.output
  end
end

function system(...)
  return vim.fn.systemlist(...)
end

function requirex(require_string, do_assert)
  local ok, out = pcall(require, require_string)

  if ok then
    return out
  end

  logger:debug(out)

  if do_assert then
    error(out)
  end
end

function glob(d, expr, nosuf, alllinks)
  nosuf = nosuf == nil and true or false
  return vim.fn.globpath(d, expr, nosuf, true, alllinks) or {}
end

--- Only works for user and doom dirs
function loadfilex(s)
  s = strsplit(s, "%.")
  local fname

  local function _loadfile(p)
    local loaded
    if Path.is_dir(p) then
      loaded = loadfile(Path.join(p, "init.lua"))
    else
      p = p .. ".lua"
      loaded = loadfile(p)
    end

    return loaded and loaded()
  end

  if s[1] == "user" then
    return _loadfile(Path.join(os.getenv "HOME", ".nvim", unpack(s)))
  elseif s[1] then
    return _loadfile(Path.join(vim.fn.stdpath "config", "lua", unpack(s)))
  end
end

local function process_input(key, value)
  local out = {}
  local default, completion, cancelreturn, prompt, default, highlight, post, required
  required = value.required
  post = value.post
  prompt = (value.prompt or value[1] or key) .. " > "
  default = value.default or value[2]
  cancelreturn = value.cancelreturn
  highlight = value.highlight
  completion = value[3] or value.completion

  local opts = {
    prompt = prompt,
    default = default,
    completion = completion,
    cancelreturn = cancelreturn,
    highlight = highlight,
  }

  local userint = trim(vim.fn.input(opts))

  if #userint == 0 then
    userint = false
  else
    userint = tonumber(userint) or userint
  end

  if post then
    userint = post(userint)
  end

  if required then
    assert(userint, "no input passed for non-optional key " .. key)
  end

  out[key] = value

  return out
end

function input(spec)
  if is_a.table(spec) then
    local res = {}

    for key, value in pairs(spec) do
      local out = process_input(key, value)
      dict.merge(res, { out })
    end

    return res
  else
    return process_input(1, unpack(spec))
  end
end

function whereis(bin)
  local out = vim.fn.system("whereis " .. bin .. [[ | cut -d : -f 2- | sed -r "s/(^ *| *$)//mg"]])

  out = trim(out)
  out = strsplit(out, " ")

  if is_empty(out) then
    return false
  end

  return out
end

function req2path(s, isfile)
  local p = strsplit(s, "[./]") or { s }
  local test

  if p[1]:match "user" then
    test = Path.join(user.paths.user, "lua", unpack(p))
  else
    test = Path.join(user.paths.config, "lua", unpack(p))
  end

  local isdir = Path.exists(test)
  isfile = Path.exists(test .. ".lua")

  if isfile and isfile then
    return test .. ".lua", "file"
  elseif isdir then
    return test, "dir"
  elseif isfile then
    return test .. ".lua", "file"
  end
end

function requirem(s)
  if not s:match "^core" then
    return
  end

  if s:match "^core%.utils" then
    return
  end

  local p = s:gsub("^core", "user")
  if not req2path(s) then
    return
  end

  local builtin, builtin_tp = req2path(s)
  local _user, user_tp = req2path(p)

  if not builtin and not _user then
    return
  elseif builtin_tp == "dir" and Path.exists(builtin .. "/init.lua") then
    builtin = requirex(s)
  elseif builtin_tp then
    builtin = requirex(s)
  end

  if user_tp == "dir" and Path.exists(Path.join(_user, "init.lua")) then
    _user = requirex(s)
  else
    _user = requirex(s)
  end

  if is_table(builtin) and is_table(_user) then
    return dict.merge(copy(builtin), { _user })
  end

  return builtin
end

function reqloadfile(req_path)
  local tp
  req_path, tp = req2path(req_path)
  if req_path and tp == "file" then
    return loadfile(req_path)()
  end
end

function getpid(pid)
  if not is_number(pid) then
    return false
  end

  local out = system("ps --pid " .. pid .. " | tail -n -1")
  out = list.map(out, trim)
  out = list.filter(out, function(x)
    return #x ~= 0
  end)

  if #out > 0 then
    if string.match(out[1], "error") then
      return false, out
    end

    return true
  end

  return false
end

function killpid(pid, signal)
  if not is_number(pid) then
    return false
  end

  signal = signal or ""
  local out = system("kill -s " .. signal .. " " .. pid)
  if #out == 0 then
    return false
  else
    return false
  end

  return true
end

function mkcommand(name, callback, opts)
  opts = copy(opts or {})
  local use = vim.api.nvim_create_user_command
  local buf

  if opts.buffer then
    buf = opts.buffer == true and buffer.current() or opts.buffer
    use = vim.api.nvim_buf_create_user_command
  end

  opts.buffer = nil
  if buf then
    return use(buf, name, callback, opts)
  end

  return use(name, callback, opts)
end
