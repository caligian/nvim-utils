local list = require 'lua-utils.list'
local buffer = require 'nvim-utils.buffer'
local python = {}

function python.mark_block(bufnr, linenum)
  local buffer_lc = buffer.line_count(bufnr)
  local blocks = {
    "async def", "def", "class",
    "if", "elif", "else", "while", "for",
    "match",
  }
  blocks = list.map(blocks, function(pattern)
    return ('^%s*' .. pattern .. '%s')
  end)
  local is_block = function (line)
    for _, block in ipairs(blocks) do
      if line:match(block) then
        return true
      end
    end
    return false
  end
  local get_indent = function (line)
    local ws = line:match '^%s*'
    if ws then
      return #ws
    else
      return 0
    end
  end
  local get_block_pos = function (_linenum)
    local line = buffer.get_line(bufnr, _linenum)
    if not is_block(line) then
      return
    end

    local block_indent = get_indent(line)
    for i = linenum, buffer_lc do
      local curline = buffer.get_line(bufnr, i)
      local indent = get_indent(curline)

      if indent then
        
      end
    end
  end

  print(get_block_pos(linenum))
end

local bufnr = buffer.current()
python.mark_block(bufnr, buffer.get_linenum(bufnr))

function python.parse_block(bufnr)

end
