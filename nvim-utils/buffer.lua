local utils = require 'lua-utils'
local list = utils.list
local dict = utils.dict
local types = utils.types
local buffer = {}
user_config.buffer = buffer

buffer.call = vim.api.nvim_buf_call
buffer.del_keymap = vim.api.nvim_buf_del_keymap
buffer.del_var = vim.api.nvim_buf_del_var
buffer.get_var = vim.api.nvim_buf_get_var
buffer.set_var = vim.api.nvim_buf_set_var
buffer.get_lines = vim.api.nvim_buf_get_lines
buffer.get_text = vim.api.nvim_buf_get_text
buffer.get_name = vim.api.nvim_buf_get_name
buffer.is_valid = vim.api.nvim_buf_is_valid
buffer.line_count = vim.api.nvim_buf_line_count
buffer.set_keymap = vim.api.nvim_buf_set_keymap
buffer.set_name = vim.api.nvim_buf_set_name
buffer.set_text = vim.api.nvim_buf_set_text
buffer.set_lines = vim.api.nvim_buf_set_lines
buffer.winid = vim.fn.bufwinid
buffer.winnr = vim.fn.bufwinnr
buffer.get_name = vim.api.nvim_buf_get_name
buffer.name = buffer.get_name
buffer.get_winid = vim.fn.bufwinid
buffer.get_winnr = vim.fn.bufwinnr
buffer.winid = vim.fn.bufwinid
buffer.winnr = vim.fn.bufwinnr
buffer.set_current = vim.api.nvim_set_current_buf
buffer.get_current = vim.api.nvim_get_current_buf
buffer.current = buffer.get_current
buffer.length = buffer.line_count

function buffer.delete(bufnr, force)
  force = ifnil(force, true, false)
  vim.api.nvim_buf_delete(bufnr, {force = true})
end

buffer.del = buffer.delete

function buffer.exists(bufnr)
  return vim.fn.bufexists(bufnr) == 1
end

function buffer.loaded(bufnr)
  return vim.fn.bufloaded(bufnr) == 1
end

function buffer.get_opt(bufnr, name)
  return vim.api.nvim_get_option_value(name, {buf = bufnr})
end

function buffer.set_opt(bufnr, name, value)
  return vim.api.nvim_set_option_value(name, value, {buf = bufnr})
end

function buffer.get(name, create)
  name = name or vim.fn.tempname()
  return vim.fn.bufnr(name, create)
end

function buffer.wordcount(bufnr)
  return buffer.call(bufnr, function()
    return vim.fn.wordcount()
  end)
end

function buffer.get_line(bufnr, linenum)
  local ok, msg = pcall(
    vim.api.nvim_buffer.get_lines,
    bufnr, linenum, linenum+1, true
  )
  if ok then
    if list.length(msg) > 0 then
      return msg[1]
    end
  end
end

function buffer.get_linenum(bufnr)
  return buffer.call(bufnr, function ()
    return vim.fn.getpos(".")[2] - 1
  end)
end

function buffer.current_line(bufnr)
  return buffer.call(bufnr, function ()
    return vim.fn.getline('.')
  end)
end

function buffer.create(name, unlisted)
  local bufnr = buffer.get(name, true)
  if unlisted then
    buffer.set_opt(bufnr, 'buflisted', false)
  else
    buffer.set_opt(bufnr, 'buflisted', true)
  end
  return bufnr
end

function buffer.create_unlisted(name)
  return buffer.get(name, true)
end

function buffer.listed(bufnr)
  return buffer.get_opt(bufnr, 'buflisted') == true
end

function buffer.unlisted(bufnr)
  return buffer.get_opt(bufnr, 'buflisted') == false
end

function buffer.append_lines(bufnr, lines, linenum)
  if type(lines) == 'string' then lines = vim.split(lines, "\n") end
  if not linenum then linenum = buffer.line_count(bufnr) else linenum = linenum + 1 end
  vim.api.nvim_buffer.set_lines(bufnr, linenum, linenum, false, lines)
  return true
end

function buffer.prepend_lines(bufnr, lines, linenum)
  if type(lines) == 'string' then lines = vim.split(lines, "\n") end
  if not linenum then linenum = buffer.line_count(bufnr) - 1 end
  vim.api.nvim_buffer.set_lines(bufnr, linenum, linenum, false, lines)
  return true
end

function buffer.lines(bufnr)
  return buffer.get_lines(bufnr, 0, -1, false)
end

function buffer.as_string(bufnr)
  return list.concat(buffer.lines(bufnr), "\n")
end

function buffer.as_list(bufnr)
  return buffer.lines(bufnr)
end

function buffer.grep(bufnr, ...)
  local patterns = {...}
  local matches = function(s)
    for i=1, #patterns do
      if s:match(patterns[i]) then
        return true
      end
    end
    return false
  end
  return list.filter(buffer.lines(bufnr), matches)
end

function buffer.write(bufnr)
  local filename = buffer.get_name(bufnr)
  buffer.call(bufnr, function() vim.cmd(':w!') end)
  return filename
end

function buffer.wipeout(bufnr)
  buffer.call(bufnr, function () vim.cmd('bwipeout! %') end)
  return true
end

function buffer.visible(bufnr)
   return buffer.winid(bufnr) ~= -1
end

function buffer.hide(bufnr, force)
  local winid = buffer.winid(bufnr)
  if winid == -1 then return end
  vim.api.nvim_win_close(winid, force)
  return true
end

function buffer.split_current(direction, resize)
  if direction == 'right' or direction == 'vsplit' or direction == 'v' then
    vim.cmd 'vsplit | wincmd l'
    if resize then
      vim.cmd(sprintf('vert resize %s', tostring(resize)))
    end
  else
    vim.cmd 'split | wincmd j'
    if resize then
      vim.cmd(sprintf('resize %s', tostring(resize)))
    end
  end
end

function buffer.split(bufnr, direction, resize)
  buffer.call(bufnr, function ()
    if direction == 'right' or direction == 'vsplit' or direction == 'v' then
      vim.cmd 'vsplit | wincmd l'
      if resize then
        vim.cmd(sprintf('vert resize %s', tostring(resize)))
      end
    else
      vim.cmd 'split | wincmd j'
      if resize then
        vim.cmd(sprintf('resize %s', tostring(resize)))
      end
    end
  end)
end

function buffer.split_current_right(resize)
  return buffer.split_current('right', resize)
end

function buffer.split_current_below(resize)
  return buffer.split_current('s', resize)
end

function buffer.split_below(bufnr, resize)
  return buffer.split(bufnr, 's', resize)
end

function buffer.split_right(bufnr, resize)
  return buffer.split(bufnr, 'right', resize)
end

function buffer.create_temp(name, opts)
  opts = opts or {}
  name = name or vim.fn.tempname()
  local on_input = opts.on_input
  local contents = opts.contents or opts.text or opts.string
  local bufnr = buffer.create_unlisted(name)
  local split = opts.split
  local resize = opts.resize
  local write = opts.write
  local delete_after = ifnil(opts.delete_after, opts.rm_after, nil)
  local comment = ifelse(on_input, true, opts.comment)
  contents = contents and ifelse(
    types.string(contents),
    vim.split(contents, "\n"),
    contents
  )
  contents = contents and comment and list.map(contents, function (x)
    return '# ' .. x
  end) or contents

  buffer.set_lines(bufnr, 0, -1, false, {})

  if contents then
    if on_input then list.push(contents, "") end
    buffer.set_lines(bufnr, 0, -1, true, contents)
  end

  if split then
    vim.keymap.set('n', 'q', '<cmd>bwipeout! %<CR>', {buffer = bufnr})
    buffer.split(buffer.current(), split, resize)
    buffer.set_current(bufnr)
    buffer.call(bufnr, function () vim.cmd 'normal! G' end)
  end

  if on_input then
    vim.keymap.set(
      'n', '<C-c><C-c>',
      function ()
        local lines = buffer.lines(bufnr)
        lines = list.filter(lines, function (x)
          if not x:match('^%s*#') then return x end
        end)

        if not (#lines == 0 or (#lines == 1 and lines[1] == '')) then
          on_input(lines)
        else
          on_input(false)
        end

        vim.cmd('bwipeout! %')
      end,
      {buffer = bufnr}
    )
  end

  if write then
    buffer.write(bufnr)
    if delete_after then
      local timer = vim.uv.new_timer()
      timer:start(delete_after, 0, vim.schedule_wrap(function ()
        pcall(vim.fs.rm, name)
        buffer.wipeout(bufnr)
        timer:stop()
        timer:close()
      end))
    end
  end

  return bufnr
end

function buffer.open_term(cmd, cwd)
  local temp_bufnr = buffer.create(nil, false)
  local job_id, termbufnr
  local chansend = vim.api.nvim_chan_send

  buffer.call(temp_bufnr, function ()
    vim.cmd('term')
    termbufnr = buffer.current()
    job_id = vim.b.terminal_job_id
    user_config.terminals[job_id] = termbufnr
    cmd = ifelse(
      cwd,
      sprintf('cd "%s" && %s', cwd, cmd),
      cmd
    )

    printf(
      'Started terminal with command: %s',
      cmd,
      cwd:gsub(os.getenv('HOME'), '~')
    )

    chansend(job_id, cmd .. "\n")

    vim.api.nvim_create_autocmd('TermClose', {
      buffer = termbufnr,
      desc = 'Delete terminal buffer',
      callback = function (args) buffer.del(args.buf) end
    })

    vim.keymap.set(
      'n', 'q', ':hide<CR>', {buffer = termbufnr}
    )

    buffer.set_opt(termbufnr, 'buflisted', false)
  end)

  buffer.del(temp_bufnr)

  return termbufnr, job_id
end

function buffer:dirname(bufnr)
  return vim.fs.dirname(buffer.name(bufnr))
end

function buffer.filetype(bufnr)
  return buffer.get_opt(bufnr, 'filetype')
end

function buffer.root_dir(bufnr, pat, depth)
  bufnr = bufnr or vim.fn.bufnr()
  local bufname = buffer.name(bufnr)
  local ws = vim.fs.find(pat, {upward = true, limit = depth or 4})
  pat = pat or {'.git'}
  depth = depth or 4

  if #ws == 0 then
    return vim.fs.dirname(bufname)
  else
    ws = vim.fs.dirname(ws[1])
    user_config.workspaces[bufnr] = ws
    user_config.workspaces[bufname] = ws
    dict.set(user_config.workspaces, {ws, bufnr}, true)
    dict.set(user_config.workspaces, {ws, bufname}, true)

    return ws
  end
end

function buffer.workspace(bufnr, opts)
  opts = opts or {}
  local pat = opts.pattern or opts.pat or {'.git'}
  local depth = opts.depth or opts.check_depth or 4
  local callback = opts.callback
  bufnr = bufnr or vim.fn.bufnr()
  local exists = user_config.workspaces[bufnr]

  if exists and callback then
    return callback(exists)
  elseif exists then
    return exists
  elseif pat then
    if callback then
      return callback(buffer.root_dir(bufnr, pat, depth))
    else
      return buffer.root_dir(bufnr, pat, depth)
    end
  end
end

return buffer
