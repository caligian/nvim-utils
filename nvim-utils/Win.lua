Win = ns()

Winid = ns()
Winid:include(nvim.win)

Tabpage = ns()
Tabpage:include(nvim.tabpage)

local call = vim.api.nvim_win_call
wrap = identity

local function valid_winid(winid, f)
  local ok, msg = pcall(vim.api.nvim_win_is_valid, winid)

  if not ok then
    return false, msg
  else
    return f(winid)
  end
end

local function valid_winnr(winnr, f)
  local exists = vim.fn.winbufnr(winnr)

  if exists == -1 then
    return false, "expected valid winnr, got " .. dump(winnr)
  else
    return f(winnr)
  end
end

function Winid.call(winid, f)
  return valid_winid(winid, function()
    return call(winid, f)
  end)
end

function Win.nr2id(winnr)
  return valid_winnr(winnr, function()
    local id = vim.fn.win_getid(winnr)

    if id == 0 then
      return
    end

    return id
  end)
end

function Winid.exists(winnr)
  return valid_winid(winnr, function()
    return true
  end)
end

function Win.exists(winnr)
  return valid_winnr(winnr, function()
    return true
  end)
end

function Winid.id2nr(winid)
  return valid_winid(winid, function()
    local ok = vim.fn.win_id2win(winid)

    if ok == 0 then
      return
    end

    return ok
  end)
end

Winid.winnr = Winid.id2nr

function Winid.bufnr(winid)
  return valid_winid(winid, function()
    local winnr = Winid.winnr(winid)

    if not winnr then
      return
    end

    local bufnr = vim.fn.winbufnr(winnr)

    return bufnr
  end)
end

function Winid.bufname(winid)
  return valid_winid(winid, function()
    local bufnr = Winid.bufnr(winid)
    return defined(bufnr and vim.api.nvim_buf_get_name(bufnr))
  end)
end

function Win.winnr(expr)
  if expr == nil then
    return vim.fn.winnr()
  end

  return vim.fn.winnr(expr)
end

Win.winid = Win.nr2id

function Win.current()
  return vim.fn.winnr()
end

function Winid.current()
  return Win.nr2id(Win.current())
end

function Win.current_id()
  return Winid.current()
end

function Win.height(winnr)
  return valid_winnr(winnr, vim.fn.winheight)
end

function Win.width(winnr)
  return valid_winnr(winnr, vim.fn.winwidth)
end

function Win.size(winnr)
  return valid_winnr(winnr, function()
    local width, height = Win.width(winnr), Win.height(winnr)

    if not width or not height then
      return
    end

    return { width, height }
  end)
end

function Winid.set_vars(winid, vars)
  return valid_winid(winid, function()
    local out = {}

    for key, value in pairs(vars) do
      out[key] = vim.api.nvim_win_set_var(winid, key, value)
    end

    return out
  end)
end

function Winid.get_options(winid, options)
  return valid_winid(winid, function()
    local out = {}

    for i = 1, #options do
      out[options[i]] = vim.api.nvim_win_get_option(winid, options[i])
    end

    return out
  end)
end

function Winid.set_options(winid, options)
  return valid_winid(winid, function()
    local out = {}

    for key, value in pairs(options) do
      out[key] = vim.api.nvim_win_set_option(winid, key, value)
    end

    return out
  end)
end

function Winid.get_vars(winid, vars)
  return valid_winid(winid, function()
    local out = {}

    for i = 1, #vars do
      out[vars[i]] = vim.api.nvim_win_get_var(winid, vars[i])
    end

    return out
  end)
end

function Winid.pos(winid, expr)
  return Winid.call(winid, function()
    local pos = vim.fn.getpos(expr or ".")
    return {
      bufnr = vim.fn.bufnr(),
      winid = winid,
      winnr = Winid.id2nr(winid),
      row = pos[2],
      col = pos[3],
      offset = pos[4],
    }
  end)
end

Winid.getpos = Winid.pos

function Winid.restcmd(winid)
  return Winid.call(winid, function()
    return vim.fn.winrestcmd()
  end)
end

function Winid.focus(winid)
  return valid_winid(winid, function()
    return vim.fn.win_gotoid(winid) ~= 0
  end)
end

function Winid.restview(winid, view)
  return Winid.call(winid, function()
    if is_a.string(view) then
      vim.cmd(view)
    else
      vim.fn.winrestview(view)
    end

    return true
  end)
end

function Winid.saveview(winid)
  return Winid.call(winid, function()
    return vim.fn.winsaveview()
  end)
end

function Winid.current_line(winid)
  return Winid.call(winid, function()
    return vim.fn.getline "."
  end)
end

function Winid.linenum(winid)
  return Winid.call(winid, function()
    return vim.fn.line "."
  end)
end

function Tabpage.layouts(tab)
  local out

  if tab == nil then
    out = vim.fn.winlayout()
  else
    out = vim.fn.winlayout(tab)
  end

  if #out == 0 then
    return
  end

  return out
end

function Winid.virtualcol(winid)
  return Winid.call(winid, function()
    return vim.fn.wincol()
  end)
end

function Win.bufname(winnr)
  return vim.api.nvim_buf_get_name(vim.fn.winbufnr(winnr))
end

function Win.bufnr(winnr)
  return vim.fn.winbufnr(winnr)
end

function Win.move(from_winnr, towinnr, opts)
  if not Win.exists(towinnr) then
    return
  end

  vim.fn.win_splitmove(from_winnr, towinnr, opts or { right = true })

  return true
end

function Win.screenpos(winnr)
  winnr = winnr or Win.current()

  if not Win.exists(winnr) then
    return
  end

  return vim.fn.win_screenpos(winnr)
end

function Win.move_statusline(winnr, offset)
  return vim.fn.win_move_statusline(winnr, offset) ~= 0
end

function Win.move_separator(winnr, offset)
  return vim.fn.win_move_separator(winnr, offset) ~= 0
end

function Winid.tabpage(winid)
  return valid_winid(winid, function()
    local out = vim.fn.win_id2tabwin(winid)
    if out[1] == 0 and out[2] == 0 then
      return
    end

    return out
  end)
end

function Win.type(winnr)
  return valid_winnr(winnr, vim.fn.win_gettype)
end

function Winid.col(winid, expr)
  return Winid.call(winid, function()
    expr = expr or "."
    return vim.fn.col(expr)
  end)
end

function Winid.row(winid, expr)
  return Winid.call(winid, function()
    expr = expr or "."
    return vim.fn.line(expr)
  end)
end

function Winid.curpos(winid)
  local row = Winid.row(winid)
  if not row then
    return
  end

  local col = Winid.col(winid)
  if not col then
    return
  end

  return { row = row, col = col }
end

function Winid.range(winid)
  return Winid.call(winid or Winid.current(), function()
    if vim.fn.mode() == "v" then
      vim.cmd "normal! "
    end

    local _, csrow, cscol, _ = unpack(vim.fn.getpos "'<")
    local _, cerow, cecol, _ = unpack(vim.fn.getpos "'>")

    if csrow > cerow or cscol > cecol then
      return
    end

    return {
      bufnr = Winid.bufnr(winid),
      row = { csrow, cerow },
      col = { cscol, cecol },
    }
  end)
end

local function range_text(buf, ...)
  local args = { ... }
  args = list.map(args, function(x)
    return x - 1
  end)

  args[#args + 1] = {}

  return vim.api.nvim_buf_get_text(buf, unpack(args))
end

function Winid.range_text(winid)
  return valid_winid(winid, function()
    local range = Winid.range(winid)
    if not range then
      return
    end

    local csrow, cerow = unpack(range.row)
    local cscol, cecol = unpack(range.col)
    local buf = Winid.bufnr(winid)

    return range_text(buf, csrow, cscol, cerow, cecol)
  end)
end

function Winid.is_visible(winid)
  return Winid.winnr(winid) and winid
end

Winid.getpos = Winid.pos
Winid.option = Winid.get_option
Winid.var = Winid.get_var

local exclude = {
  id2nr = true,
  bufnr = true,
  current = true,
  bufname = true,
  nr2id = true,
  winnr = true,
  winid = true,
  current_id = true,
}

dict.each(Win, function(key, _)
  if not exclude[key] then
    Winid[key] = function(winid, ...)
      local ok, msg = Winid.winnr(winid)
      local value = Win[key]

      if ok then
        return value(ok, ...)
      else
        return false, msg
      end
    end
  end
end)

dict.each(Winid, function(key, value)
  if not exclude[key] and not Win[key] then
    Win[key] = function(winnr, ...)
      local ok, msg = Win.winid(winnr)

      if ok then
        return value(ok, ...)
      else
        return false, msg
      end
    end
  end
end)

current_winnr = Win.current
current_winid = Win.current_id
