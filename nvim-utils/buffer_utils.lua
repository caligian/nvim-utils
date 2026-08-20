require 'lua-utils'

local list = require 'lua-utils.list'
local dict = require 'lua-utils.dict'
local path = require 'lua-utils.path_utils'
local copy = vim.deepcopy
local utils = {}
local curbuf = vim.fn.bufnr

---Get current buffer
---@return number
function utils.current()
  return vim.fn.bufnr()
end

---@param bufnr? number
---@param fn fun(): any
---@param should_pcall boolean
---@return boolean, string?
---@overload fun(bufnr: number, fn: fun(): any): any
---@overload fun(bufnr: number, fn: (fun(): any), should_pcall: 'true'): boolean, any
function utils.call(bufnr, fn, should_pcall)
  bufnr = bufnr or vim.fn.bufnr()
  if should_pcall then
    return pcall(vim.api.nvim_buf_call, bufnr, fn)
  else
    return vim.api.nvim_buf_call(bufnr, fn)
  end
end

---@param bufnr? number
---@param fn (fun(): any)
---@return boolean, any
function utils.pcall(bufnr, fn)
  return utils.call(bufnr, fn, true)
end

---@param bufnr number
---@param assert? boolean Throw error on non-existence
---@return boolean,string?
function utils.exists(bufnr, assert)
  bufnr = bufnr or vim.fn.bufnr()
  local ok = vim.api.nvim_buf_is_valid(bufnr)

  if not ok then
    if not assert then
      return false
    else
      error('bufnr: Expected valid buffer, got ' .. tostring(bufnr))
    end
  end

  return true
end

---@param bufnr number
---@return boolean
function utils.assert_exists(bufnr)
  return utils.exists(bufnr, true)
end

---@param bufnr number
---@return boolean
function utils.is_invalid(bufnr)
  return not buffer.is_valid(bufnr)
end

---@param bufnr? number
---@return boolean
function utils.is_empty(bufnr)
  utils.assert_is_valid(bufnr)
  local lc = vim.api.nvim_buf_line_count(bufnr)
  local line = vim.api.nvim_buf_call(bufnr, function()
    return vim.fn.getline(1)
  end)

  if lc == 1 and line == "" then
    return true
  elseif lc == 0 then
    return true
  else
    return false
  end
end

---@param bufnr? number
---@return boolean
function utils.is_nonempty(bufnr)
  return not utils.is_empty(bufnr)
end

---@param bufnr? number
---@return boolean
function utils.is_visible(bufnr)
  return vim.fn.bufwinid(bufnr) ~= -1
end

---@param bufnr? number
---@return boolean
function utils.is_invisible(bufnr)
  return vim.fn.bufwinid(bufnr) == -1
end

---@param bufnr? number
---@return boolean
function utils.is_modifiable(bufnr)
  utils.assert_exists(bufnr)
  return vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
end

---@param bufnr? number
---@return boolean
function utils.is_listed(bufnr)
  utils.assert_exists(bufnr)
  return vim.api.nvim_get_option_value('buflisted', { buf = bufnr })
end

---@param bufnr? number
---@param markers string|string[]
---@param depth? number (depth 4)
---@return boolean, string?
function utils.in_dir(bufnr, markers, depth)
  utils.assert_exists(bufnr)

  local check_file = function(dir)
    for i = 1, #markers do
      local marker = dir .. '/' .. markers[i]
      if path.is_file(marker) or path.is_dir(marker) or path.is_link(marker) then
        return dir
      else
        return false
      end
    end
  end
  depth = depth or 3
  local currentdir = path.dirname(vim.api.nvim_buf_get_name(bufnr))
  markers = as_list(markers)
  local home = os.getenv("HOME")

  for _ = 1, depth do
    if currentdir == '/' or home == currentdir then
      local ok = check_file(currentdir)
      if not ok then
        return false
      end

      return true
    elseif check_file(currentdir) then
      return true
    else
      currentdir = path.dirname(currentdir)
    end
  end

  return false
end

---@param bufnr? number
---@param depth? number (default: 3)
---@return boolean
function utils.in_git_dir(bufnr, depth)
  return utils.in_dir(bufnr, ".git", depth)
end

---@param bufnr? number
---@param depth? number (default: 3)
---@return boolean
function utils.in_nix_dir(bufnr, depth)
  return utils.in_dir(bufnr, { "shell.nix", "default.nix" }, depth)
end

---@param bufnr? number
---@param fn string|string[]|(fun(buf: string): any)
---@param start_row? number (default: 0)
---@param end_row? number (default: -1)
---@return string|string[]
function utils.filter(bufnr, fn, start_row, end_row)
  utils.assert_exists(bufnr)

  local is_pat = is.string(fn)
  local is_list_pat = is.pure_list(fn)
  local is_fun = is.fun(fn)
  local check = function(line)
    if is_pat and string.match(line, fn) then
      return true
    elseif is_list_pat then
      for i = 1, #fn do
        if string.match(line, fn[i]) then
          return true
        end
      end
    elseif is_fun and fn(line) then
      return true
    end
  end
  local lines = vim.api.nvim_buf_get_lines(
    bufnr,
    start_row or 0, end_row or -1,
    false
  )

  return list.filter(lines, check)
end

---@param bufnr? number
---@return string?
function utils.get_filetype(bufnr)
  return utils.get_opt(bufnr, 'filetype')
end

---@param bufnr? number
---@param name string
---@return any
function utils.get_opt(bufnr, name)
  utils.assert_exists(bufnr)
  return vim.api.nvim_get_option_value(name, { buf = bufnr })
end

---@param bufnr? number
---@param names string[]
---@return table<string,any>
function utils.get_opts(bufnr, names)
  utils.assert_exists(bufnr)
  res = {}

  for _, name in ipairs(names) do
    res[name] = vim.api.nvim_get_option_value(name, { buf = bufnr })
  end

  return res
end

---@param bufnr? number
---@param name string
---@param value any
function utils.set_opt(bufnr, name, value)
  utils.assert_exists(bufnr)
  vim.api.nvim_set_option_value(name, value, { buf = bufnr })
end

---@param bufnr? number
---@param values table<string, any>
---@return table<string,boolean>
function utils.set_opts(bufnr, values)
  utils.assert_exists(bufnr)

  local res = {}
  for k, v in pairs(values) do
    res[k] = utils.set_opt(bufnr, k, v)
  end

  return res
end

---@param bufnr? number
---@param var string
---@return boolean
function utils.del_var(bufnr, var)
  utils.assert_exists(bufnr)
  local ok, _ = pcall(vim.api.nvim_buf_del_var, bufnr, var)
  return ok
end

---@param bufnr? number
---@param var string
---@return any
function utils.get_var(bufnr, var)
  utils.assert_exists(bufnr)
  local ok, msg_or_value = pcall(vim.api.nvim_buf_get_var, bufnr, var)
  if ok then
    return msg_or_value
  end
end

---@param bufnr? number
---@param names string[]
---@return table<string,any>
function utils.get_vars(bufnr, names)
  utils.assert_exists(bufnr)
  res = {}

  for _, name in ipairs(names) do
    res[name] = utils.get_var(bufnr, name)
  end

  return res
end

---@param bufnr? number
---@param var string
---@param value any
---@return boolean
function utils.set_var(bufnr, var, value)
  utils.assert_exists(bufnr)
  local ok, _ = pcall(vim.api.nvim_buf_set_var, bufnr, var, value)
  return ok
end

---@param bufnr? number
---@param values table<string,any>
---@return table<string,boolean>
function utils.set_vars(bufnr, values)
  utils.assert_exists(bufnr)

  local res = {}
  for var, value in ipairs(values) do
    res[var] = utils.set_var(bufnr, var, value)
  end

  return res
end

---@param bufnr? number
---@return boolean
function utils.is_loaded(bufnr)
  utils.assert_exists(bufnr)
  return vim.fn.bufloaded(bufnr) == 1
end

---@param bufnr? number
---@return boolean
function utils.is_listed(bufnr)
  utils.assert_exists(bufnr)
  return vim.fn.buflisted(bufnr) == 1
end

---@param bufnr? number
---@return boolean
function utils.is_unlisted(bufnr)
  utils.assert_exists(bufnr)
  return vim.fn.buflisted(bufnr) ~= 1
end

---@param bufnr? number
---@param start_row number
---@param end_row   number
---@param lines string[]|string
---@return boolean, string?
function utils.set_lines(bufnr, start_row, end_row, lines)
  utils.assert_exists(bufnr)
  lines = type(lines) == 'string' and vim.split(lines, "\n") or lines
  local ok, msg = pcall(vim.api.nvim_buf_set_lines, bufnr, start_row, end_row, false, lines)

  if ok then
    return true, nil
  else
    return false, msg
  end
end

---@param bufnr? number
---@param linenum number
---@return string?
function utils.get_line(bufnr, linenum, strict_indexing)
  utils.assert_exists(bufnr)
  local ok, msg = pcall(vim.api.nvim_buf_get_lines, bufnr, linenum, linenum + 1, strict_indexing)

  if ok then
    if #msg == 1 and msg[1] == "" then
      return nil
    else
      return msg[1]
    end
  end
end

---@param bufnr? number
---@param start_row number
---@param end_row number
---@param strict_indexing? boolean
---@return string[]?
function utils.get_lines(bufnr, start_row, end_row, strict_indexing)
  utils.assert_exists(bufnr)
  local ok, msg = pcall(vim.api.nvim_buf_get_lines, bufnr, start_row, end_row, strict_indexing)

  if ok then
    if #msg == 1 and msg[1] == "" then
      return nil
    elseif #msg == 0 then
      return nil
    else
      return msg
    end
  else
    return nil
  end
end

---@param bufnr? number
---@return number
function utils.get_current_linenum(bufnr)
  return utils.call(bufnr, function()
    return vim.fn.getpos(".")[2] - 1
  end)
end

---@param bufnr? number
---@return string
function utils.get_current_line(bufnr)
  return utils.call(bufnr, function()
    return vim.fn.getline('.')
  end)
end

---@param bufnr? number
---@return string[]?
function utils.as_list(bufnr)
  return utils.get_lines(bufnr, 0, -1, false)
end

---@param bufnr? number
---@param join_sep? string (default: \\n)
---@return string?
function utils.as_string(bufnr, join_sep)
  local lines = utils.as_list(bufnr)
  if lines then
    return table.concat(lines, join_sep or "\n")
  end
end

---@param bufnr? number
---@param start_row number
---@param start_col number
---@param end_row number
---@param end_col number
---@param replacement string|string[]
---@return boolean
function utils.set_text(bufnr, start_row, start_col, end_row, end_col, replacement)
  utils.assert_exists(bufnr)
  local ok, _ = pcall(vim.api.nvim_buf_set_text, bufnr, start_row, start_col, end_row, end_col, replacement)
  return ok
end

---@param bufnr? number
---@param start_row number
---@param start_col number
---@param end_row number
---@param end_col number
---@return string[]?
function utils.get_text(bufnr, start_row, start_col, end_row, end_col)
  utils.assert_exists(bufnr)
  local ok, lines = pcall(vim.api.nvim_buf_get_text, bufnr, start_row, start_col, end_row, end_col, {})

  if ok then
    return lines
  end
end

---@param bufnr? number
---@return string?
function utils.get_name(bufnr)
  local fname = vim.api.nvim_buf_get_name(bufnr or vim.fn.bufnr())
  if fname == '' then
    return
  else
    return fname
  end
end

---@param bufnr? number
---@return string?
function utils.get_dirname(bufnr)
  local fname = utils.get_name(bufnr)
  if fname then return path.dirname(fname) end
end

---@param bufnr? number
---@return table<string|number, number>
function utils.get_word_count(bufnr)
  return utils.call(bufnr, function()
    return vim.fn.wordcount()
  end)
end

---@class buffer.get_curpos.return
---@field [1] number
---@field [2] number
---@field [3] number
---@field [4] number
---@field lnum number
---@field col number
---@field off number
---@field curswant number

---This cannot be used with vim.fn.winrestview!
---@param bufnr? number
---@return buffer.get_curpos.return?
function utils.get_curpos(bufnr)
  local winid = utils.get_winid(bufnr)
  if not winid then
    return
  end

  local out = vim.fn.getcurpos(winid)
  out[2] = out[2] - 1
  out.lnum = out[2]
  out.col = out[3]
  out.off = out[4]
  out.curswant = out[5]
  out.buf = bufnr
  out.winid = winid

  return out
end

---@param bufnr? number
---@return number?
function utils.get_winnr(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local winnr = vim.fn.bufwinnr(bufnr)
  local ok = winnr ~= -1

  if ok then
    return winnr
  else
    return
  end
end

---@param bufnr? number
---@return number?
function utils.get_winid(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  local winid = vim.fn.bufwinid(bufnr)
  local ok = winid ~= -1

  if ok then
    return winid
  else
    return
  end
end

---@return number?
function utils.get_current_winid()
  return utils.get_winid(vim.fn.bufnr())
end

---@return number?
function utils.get_current_winnr()
  return utils.get_winnr(vim.fn.bufnr())
end

---@param bufnr? number
---@param force? boolean
---@return boolean
function utils.delete(bufnr, force)
  bufnr = bufnr or vim.fn.bufnr()
  if vim.fn.bufexists(bufnr) ~= 1 then
    return false
  else
    vim.api.nvim_buf_delete(bufnr, { force = force })
    return true
  end
end

---@param bufnr? number
---@return boolean
function utils.wipeout(bufnr)
  return utils.delete(bufnr, true)
end

---@param bufnr? number
---@return boolean
function utils.unload(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if vim.fn.bufexists(bufnr) ~= 1 then
    return false
  else
    vim.api.nvim_buf_delete(bufnr, { unload = true })
    return true
  end
end

---@param bufnr? number
---@param direction? string (default: 's') 's'|'v'
---@param switch_to? number
---@param resize? number|string
---@return boolean?
function utils.split(bufnr, direction, switch_to, resize)
  bufnr = bufnr or vim.fn.bufnr()
  switch_to = switch_to or bufnr
  return utils.call(bufnr, function()
    if direction == 's' then
      vim.cmd(':split | wincmd j | b ' .. switch_to)
    else
      vim.cmd(':vsplit | wincmd l | b ' .. switch_to)
    end

    if resize then
      utils.resize(bufnr, direction, resize)
    end

    return true
  end)
end

---@param bufnr? number
---@param switch_to? number
---@param resize? number|string
---@return boolean?
function utils.split_right(bufnr, switch_to, resize)
  return utils.split(bufnr, 's', switch_to, resize)
end

---@param bufnr? number
---@param switch_to? number
---@param resize? number|string
---@return boolean?
function utils.split_below(bufnr, switch_to, resize)
  return utils.split(bufnr, 'v', switch_to, resize)
end

---Open this buffer in a new tab
---@param bufnr? number
---@return boolean
function utils.tabnew(bufnr)
  vim.cmd(':tabnew | b ' .. tostring(bufnr))
  return true
end

---Open this buffer in a new tab
---@param bufnr? number
function utils.tabedit(bufnr)
  vim.cmd(':tabedit | b ' .. tostring(bufnr))
  return true
end

---@param bufnr? number
---@return number
function utils.get_tabpage(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  return utils.call(bufnr, function()
    return vim.api.nvim_tabpage_get_number(0)
  end)
end

---@param bufnr? number
---@param direction? string (default: 's')
---@param resize? number|string (default: -5)
---@return boolean
function utils.resize(bufnr, direction, resize)
  bufnr = bufnr or vim.fn.bufnr()
  if not utils.is_visible(bufnr) then
    return false
  end

  direction = direction or ''
  resize = resize or -5

  return buffer.call(bufnr, function()
    if direction == 's' then
      vim.cmd('resize ' .. tostring(resize))
    else
      vim.cmd('vert resize ' .. tostring(resize))
    end
    return true
  end)
end

---@param bufnr? number
---@return boolean
function utils.hide(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  if not utils.is_visible(bufnr) then
    return false
  else
    utils.call(bufnr, function() vim.cmd ':call HideWindowIfPossible()' end)
    return true
  end
end

---@param bufnr? number
---@return string
function utils.as_string(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
end

---@param bufnr? number
---@return string[]
function utils.as_list(bufnr)
  bufnr = bufnr or vim.fn.bufnr()
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---@param bufnr? number
---@param event? string|string[]
---@param command string|function
---@param opts? table
---@return number
function utils.add_autocmd(bufnr, event, command, opts)
  bufnr = bufnr or curbuf()
  event = event or 'BufReadPost'
  opts = opts or {}
  opts = copy(opts)
  opts.buffer = bufnr
  opts.pattern = nil

  if is.string(command) then
    opts.command = command
  elseif callable(command) then
    opts.callback = command
  end

  local ok, msg_or_id = pcall(vim.api.nvim_create_autocmd, event, opts)
  if ok then
    return msg_or_id
  else
    error(msg_or_id)
  end
end

---@param bufnr? number
---@param mode? string|string[] keys
---@param keys string
---@param command string|fun(buf: number)
---@param opts? table
---@return boolean
function utils.add_keymap(bufnr, mode, keys, command, opts)
  bufnr = bufnr or curbuf()
  local cmd = command
  command = callable(cmd) and function()
    return cmd(bufnr)
  end or cmd
  mode = mode or 'n'
  opts = opts or {}
  opts = copy(opts)
  opts.buffer = bufnr
  local ok, msg = pcall(vim.keymap.set, mode, keys, command, opts)

  if ok then
    return true
  else
    error(msg)
  end
end

---@class buffer.new.opts.keymap
---@field [1] string|string[] mode
---@field [2] string keys
---@field [3] string|function command
---@field [4]? table options

---@class buffer.new.opts.autocmd
---@field [1] string|string[] event
---@field [2] string|function callback
---@field [3]? table rest options

---@class buffer.new.opts
---@field scratch? boolean
---@field name? string
---@field var? table<string,any>
---@field opt? table<string,any>
---@field keymaps? buffer.new.opts.keymap[]
---@field autocmds? function[]
---@field listed? boolean

---@param opts buffer.new.opts
function utils.new(opts)
  local add_autocmd = function(buf, args)
    if not is.pure_list(args) then
      errorf("Expected pure list, got [%s] %s", type(args), args)
    end

    local args_len = #args
    if args_len ~= 3 and args_len ~= 2 then
      errorf("Expected {[1] = string|string[], [2] = function|string, [3] = table?},  got %s", args)
    end

    utils.add_autocmd(buf, args[1], args[2], args[3])
  end
  local add_keymap = function(buf, args)
    if not is.pure_list(args) then
      errorf("Expected pure list, got [%s] %s", type(args), args)
    end

    local args_len = #args
    if args_len ~= 3 and args_len ~= 4 then
      errorf("Expected {[1] = string|string[], [2] = string, [3] = function|string, [4] = table?},  got %s", args)
    end

    utils.add_keymap(buf, args[1], args[2], args[3], args[4])
  end
  local bufnr

  if opts.scratch then
    bufnr = vim.api.nvim_create_buf(opts.listed, opts.scratch)
    utils.add_keymap(bufnr, 'n', 'q', utils.hide, { desc = 'Hide buffer' })
    utils.add_keymap(bufnr, 'n', 'Q', utils.wipeout, { desc = 'Delete buffer' })
  elseif opts.name then
    bufnr = vim.fn.bufadd(opts.name)
    if opts.listed then
      opts.opt = opts.opt or {}
      opts.opt.buflisted = true
    end
  else
    errorf("Expected either opts.scratch or opts.name")
  end

  if opts.keymaps then
    for _, kbd in pairs(opts.keymaps) do
      add_keymap(bufnr, kbd)
    end
  end

  if opts.autocmds then
    for _, au in pairs(opts.autocmds) do
      add_autocmd(bufnr, au)
    end
  end

  if opts.var then
    utils.set_vars(bufnr, opts.var)
  end

  if opts.opt then
    utils.set_opts(bufnr, opts.opt)
  end

  return bufnr
end

---@param listed boolean
---@param opts? buffer.new.opts
---@return number
function utils.new_scratch(listed, opts)
  opts = copy(opts or {})
  opts.scratch = true
  opts.listed = listed
  return utils.new(opts)
end

---@param name string
---@param listed? boolean
---@param opts? buffer.new.opts
---@return number
function utils.new_named(name, listed, opts)
  opts = copy(opts or {})
  opts.name = name
  opts.scratch = false
  opts.listed = listed
  return utils.new(opts)
end

---@param bufnr? number
---@return boolean
function utils.map_q(bufnr)
  utils.add_keymap(bufnr, 'n', 'q', utils.hide, { desc = 'Hide buffer' })
  utils.add_keymap(bufnr, 'n', 'Q', utils.wipeout, { desc = 'Delete buffer' })
  return true
end

function utils.get_root_dir(bufnr, pat, depth)
  bufnr = bufnr or vim.fn.bufnr()
  pat = pat or { '.git' }

  if buffer.is_invalid(bufnr) then
    return nil
  end

  local bufname = buffer.get_name(bufnr)
  local ws = vim.fs.find(pat, { upward = true, limit = depth or 4 })
  pat = pat or { '.git' }
  depth = depth or 4

  if #ws == 0 then
    return vim.fs.dirname(bufname)
  else
    ws = vim.fs.dirname(ws[1])
    user_config.workspace[bufnr] = ws
    user_config.workspace[bufname] = ws
    dict.set(user_config.workspace, { ws, bufnr }, true)
    dict.set(user_config.workspace, { ws, bufname }, true)

    return ws
  end
end

utils.rm = utils.wipeout
utils.get_filename = utils.get_name
utils.filename = utils.get_name
utils.dirname = utils.get_dirname
utils.is_valid = utils.exists
utils.is_blank = utils.is_empty
utils.has_lines = utils.is_nonempty
utils.assert_is_valid = utils.assert_exists
utils.winnr = utils.get_winnr
utils.winid = utils.get_winid

return utils
