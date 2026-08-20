require 'lua-utils'

local path = require 'lua-utils.path_utils'
local dict = require 'lua-utils.dict'
local buffer = require 'nvim-utils.buffer_utils'
local augroup = require 'nvim-utils.augroup'

user_config.template = user_config.template or {}
user_config.template.dir = user_config.path.dir.root .. '/template'
user_config.template.by_filetype = user_config.template.by_filetype or {}

---@type augroup
user_config.template.augroup = user_config.template.augroup or {}

---@alias user_config.template table<string, string[]>

---@type user_config.template
user_config.template.template = {}

local template = user_config.template

---@param name string
---@return user_config.template?
function template.load_filetype(name)
  local p = user_config.template.dir .. '/' .. name
  if not path.is_dir(p) then
    return
  end

  local patterns = path.glob(p .. '/*.*')
  if not patterns then
    return
  end

  local res = {}
  for _, pattern in ipairs(patterns) do
    local text = slurp(pattern, true)
    text = string.split(text, "\n")
    pattern = string.gsub(pattern, '%.[a-zA-Z0-9_-]+$', '')
    pattern = basename(pattern)
    res[pattern] = text
  end

  return res
end

---@return table<string, user_config.template>
function template.load()
  local ft_dirs = path.glob(user_config.template.dir .. '/*')
  for _, ft_dir in ipairs(ft_dirs) do
    local ft = basename(ft_dir)
    local res = template.load_filetype(ft)

    if res then
      user_config.template.by_filetype[ft] = res
    end
  end

  return user_config.template.by_filetype
end

---@param bufnr? number
---@param ft? string
---@return string[]?
function template.get_patterns(bufnr, ft)
  bufnr = bufnr or buffer.current()

  if not ft then
    ft = buffer.call(bufnr, function()
      return vim.bo.filetype
    end)
  end

  local expansions = user_config.template.by_filetype[ft]
  return expansions and dict.keys(expansions)
end

---@param bufnr? number
---@param ft? string
---@param patterns? string
---@return string?
function template.get_text(bufnr, ft, patterns)
  patterns = patterns and as_list(patterns)
  bufnr = bufnr or buffer.current()
  local filename = vim.api.nvim_buf_get_name(bufnr)

  if filename:sub(1, 1) ~= '/' then
    return
  end

  if not patterns then
    if not ft then
      ft = buffer.call(bufnr, function()
        return vim.bo.filetype
      end)
    end

    patterns = user_config.template.by_filetype[ft]
    if not patterns then
      return
    end
  end

  for pattern, expansion in pairs(patterns) do
    if string.match(filename, pattern) then
      return expansion
    end
  end
end

---@param bufnr? number
---@param ft? string
---@param patterns? string|string[]
---@param text? string|string[]
---@return boolean
function template.insert(bufnr, ft, patterns, text)
  patterns = patterns and as_list(patterns)
  bufnr = bufnr or buffer.current()

  if buffer.is_nonempty(bufnr) then
    return false
  end

  if not text then
    text = template.get_text(bufnr, ft, patterns)
    if not text then
      return false
    end
  end

  text = type(text) == 'string' and string.split(text, "\n") or text
  local ok, _ = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, 0, false, text)
  return ok
end

---@param ft string
---@param patterns? string|string[]
---@return boolean
function template.enable(ft, patterns)
  local exists = user_config.template.augroup[ft]
  if exists then
    return exists
  end

  if not patterns then
    if not template.by_filetype[ft] then
      return false
    else
      patterns = template.by_filetype[ft]
    end
  end

  if not patterns then
    return false
  end

  patterns = as_list(patterns)
  local group = 'user_config.template.' .. ft
  local obj = augroup(group, true)

  augroup.append(obj, 'BufRead', function(args)
    if vim.bo.modifiable then
      template.insert(args.buf)
    end
  end, {
    pattern = '*',
    desc = 'Template augroup for filetype ' .. ft
  })

  return true
end

function template.setup(overrides)
  overrides = overrides or {}
  template.load()
  dict.mergef(user_config.template.by_filetype, overrides)
  local fts = dict.keys(user_config.template.by_filetype)

  for i = 1, #fts do
    local ft = fts[i]
    template.enable(ft)
  end

  keymap.set(
    'n', '<leader>it',
    function()
      if not template.insert(buffer.current()) then
        print("No template found for current buffer")
      end
    end,
    { desc = 'Insert template', name = 'Insert template' }
  )
end

return template
