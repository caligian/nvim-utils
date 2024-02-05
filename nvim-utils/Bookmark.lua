require "nvim-utils.Kbd"
require "nvim-utils.Buffer.Buffer"
require "nvim-utils.Win"
require "nvim-utils.Autocmd"

Bookmark = ns()
Bookmark.path = user.bookmarks_path

function Bookmark.dump()
  local fh = io.open(Bookmark.path, "w")

  if fh then
    local bookmarks = dump(user.bookmarks)
    fh:write("return " .. bookmarks)
    fh:close()

    return bookmarks
  end
end

function Bookmark.load()
  local fh = io.open(Bookmark.path, "r")

  if fh then
    local bookmarks = fh:read "*a"
    bookmarks = loadstring(bookmarks)
    if bookmarks then
      local ok = bookmarks()
      if is_table(ok) then
        user.bookmarks = ok
      end
    end

    fh:close()
  else
    user.bookmarks = {}
  end

  return user.bookmarks
end

function Bookmark:__call()
  return Bookmark.load()
end

Bookmark.save = Bookmark.dump

function Bookmark.add(file_path, lines, desc)
  local obj = user.bookmarks[file_path] or { context = {} }
  local now = os.time()
  local isfile = Path.is_file(file_path)
  local isdir = Path.is_dir(file_path)

  if not isfile and not isdir then
    error(file_path .. " is neither a binary file or a directory")
  elseif lines and isdir then
    error(file_path .. " cannot use linesnum with a directory")
  elseif lines then
    context = Bookmark.get_context(file_path, lines)
  end

  obj.creation_time = now

  dict.merge(obj.context, dict.from_list(totable(lines)))

  obj.file = isfile
  obj.dir = isdir
  obj.desc = desc
  obj.path = file_path

  for key, _ in pairs(obj.context) do
    obj.context[key] = Bookmark.get_context(file_path, key)
  end

  user.bookmarks[file_path] = obj
  return obj
end

function Bookmark.del(file_path, lines)
  if not user.bookmarks[file_path] then
    return
  end

  local obj = user.bookmarks[file_path]
  if lines then
    local context = obj.context
    for _, line in ipairs(totable(lines)) do
      context[line] = nil
    end
  else
    user.bookmarks[file_path] = nil
  end

  return obj
end

function Bookmark.add_and_save(file_path, lines, desc)
  local ok = Bookmark.add(file_path, lines, desc)

  if not ok then
    return
  end

  Bookmark.save()

  return ok
end

function Bookmark.del_and_save(file_path, lines)
  local obj = Bookmark.del(file_path, lines)
  if not obj then
    return
  end

  Bookmark.save()

  return obj
end

function Bookmark.get_context(file_path, line)
  data = strsplit(Path.read(file_path), "\n")
  line = tonumber(line) or line

  if line > #data or #data < 1 then
    return nil, sprintf("invalid line %d provided for %s", line, file_path)
  end

  return data[line]
end

function Bookmark.open(file_path, line)
  if is_string(line) then
    split = line
  end

  if Path.is_dir(file_path) then
    vim.cmd(":e! " .. file_path)
  elseif Path.is_file(file_path) then
    local bufnr = Buffer.create(file_path)
    Buffer.open(bufnr)

    if line then
      if Buffer.current() == file_path then
        vim.cmd(":normal! " .. line .. "Gzz")
      else
        Buffer.call(bufnr, function()
          vim.cmd(":normal! " .. line .. "Gzz")
        end)
      end
    end
  end
end

function Bookmark.picker_results(file_path)
  local bookmarks = user.bookmarks

  if is_empty(bookmarks) then
    return
  end

  if not file_path then
    return {
      results = keys(bookmarks),
      entry_maker = function(entry)
        local obj = bookmarks[entry]

        return {
          display = entry,
          value = obj,
          path = obj.path,
          file = obj.file,
          dir = obj.dir,
          ordinal = entry,
        }
      end,
    }
  end

  local obj = user.bookmarks[file_path]

  if not obj then
    return
  elseif obj.context and is_empty(obj.context) then
    return
  end

  return {
    results = keys(obj.context),
    entry_maker = function(linenum)
      return {
        display = sprintf("%d | %s", linenum, obj.context[linenum]),
        value = linenum,
        path = obj.path,
        ordinal = linenum,
      }
    end,
  }
end

function Bookmark.create_line_picker(file_path)
  file_path = is_number(file_path) and Buffer.exists(file_path) and Buffer.get_name(file_path) or file_path
  local obj = user.bookmarks[file_path]
  local fail = not obj or obj.dir or not obj.context or is_empty(obj.context)
  if fail then
    return
  end

  user.telescope()
  local line_mod = {}

  function line_mod.default_action(prompt_bufnr)
    local obj = user.telescope:selected(prompt_bufnr)
    local linenum = obj.value
    local file_path = obj.path
    Bookmark.open(file_path, linenum, "s")
  end

  function line_mod.open(prompt_bufnr)
    local obj = user.telescope:selected(prompt_bufnr)
    vim.cmd(":b " .. obj.value)
  end

  function line_mod.del(prompt_bufnr)
    local sels = user.telescope:selected(prompt_bufnr, true)
    list.each(sels, function(obj)
      local linenum = value.value
      local file_path = obj.path
      Bookmark.del_and_save(file_path, linenum)
    end)
  end

  local context = Bookmark.picker_results(obj.path)

  local picker = user.telescope:create_picker(context, {
    line_mod.default_action,
    { "n", "o", line_mod.open },
    { "n", "x", line_mod.del },
  }, {
    prompt_title = "Bookmarked lines",
  })

  return picker
end

function Bookmark.run_line_picker(file_path)
  local picker = Bookmark.create_line_picker(file_path)
  if not picker then
    return
  end

  picker:find()
  return true
end

function Bookmark.create_picker()
  local results = Bookmark.picker_results()

  if not results then
    return
  end

  user.telescope()
  local mod = {}

  function mod.default_action(prompt_bufnr)
    local obj = user.telescope:selected(prompt_bufnr)
    if obj.file then
      local line_picker = Bookmark.create_line_picker(obj.path)
      if line_picker then
        line_picker:find()
      elseif vim.fn.bufnr(obj.path) then
        vim.cmd("b " .. obj.path)
      else
        vim.cmd("e " .. obj.path)
      end
    else
      Bookmark.open(obj.path, "s")
    end
  end

  function mod.del(prompt_bufnr)
    local sels = user.telescope:selected(prompt_bufnr, true)
    list.each(sels, function(obj)
      Bookmark.del_and_save(obj.path)
      say("removed Bookmark " .. obj.path)
    end)
  end

  return user.telescope:create_picker(
    results,
    { mod.default_action, { "n", "x", mod.del } },
    { prompt_title = "bookmarks" }
  )
end

function Bookmark.run_picker()
  local picker = Bookmark.create_picker()
  if not picker then
    return
  end

  picker:find()
  return true
end

function Bookmark.reset()
  if Path.exists(Bookmark.path) then
    Path.delete(Bookmark.path)
    return true
  end
end

function Bookmark.create_dwim_picker()
  local len = size(user.bookmarks)
  if len == 0 then
    return
  elseif len > 1 then
    return Bookmark.create_picker()
  else
    return Bookmark.create_line_picker(Buffer.get_name(Buffer.bufnr()))
  end
end

function Bookmark.run_dwim_picker()
  local picker = Bookmark.create_dwim_picker()

  if picker then
    picker:find()
  end

  return true
end

function Bookmark.set_mappings(mappings)
  Kbd.from_dict(mappings or require_config "bookmarks" or {})
end
