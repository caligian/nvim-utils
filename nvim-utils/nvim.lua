require "nvim-utils.state"

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
    s = not is_string(s) and dump(s) or s
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

function requirex(require_string)
  local ok, msg = pcall_warn(require, require_string)
  if not ok then
    return ok, msg
  else
    return msg
  end
end

function glob(d, expr, nosuf, alllinks)
  nosuf = nosuf == nil and true or false
  return vim.fn.globpath(d, expr, nosuf, true, alllinks) or {}
end

--- Only works for user and doom dirs
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

function loadfilex(path)
  local ok, msg = loadfile(path)
  if not ok then
    logger:warn(msg)
  end

  return ok--[[@as function]]()
end

function reqloadfilex(path)
  path = req2path(path)
  if not path then
    return
  end

  return loadfilex(path)
end

function getpid(pid)
  if not is_number(pid) then
    return false
  end

  local out = system("ps --pid " .. pid .. " | grep -Ev 'PID TTY'")
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


