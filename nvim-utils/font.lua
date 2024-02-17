if not vim.fn.has "gui" then
  return
end

local nvim_exec = vim.api.nvim_exec2

--- When called, load current font
--- @class guifont
--- @field name string font name
--- @field height number current height (default: 13)
--- @field opts? string other options
--- @overload fun(): nil
local current_font = user.current_font or ns "guifont"
user.current_font = current_font
user.font = "Cousine Nerd Font:h13"

function current_font:validate()
  local exists = system('fc-list | grep -i "' .. self.name .. '"')

  for i = 1, #exists do
    if exists[i]:match(self.name) then
      return self
    end
  end

  logger:warn('invalid font ' .. dump(self.name) .. ', falling back to Liberation Mono')

  self.name = 'Liberation Mono'
  return self
end

function current_font:__call(full_font)
  local name, opts
  local height = 13

  if full_font or user.font then
    full_font = full_font or user.font
    name, opts = full_font:match "^%s*([^:]+):?(.*)"
  else
    local font = nvim_exec("set guifont?", { output = true }).output
    name, opts = font:match "^%s*guifont=([^:]+):?(.*)"
  end

  if opts then
    local height_pat = ":?h([0-9]+)"
    local height = opts:match(height_pat)
    opts = opts:gsub(height_pat, "")
    opts = #opts > 0 and opts or nil
  end

  self.name = name
  self.height = tonumber(height) --[[@as number]]
  self.opts = opts

  self:validate()

  return self
end

function current_font:__tostring()
  if self.opts then
    return ("%s:h%d:%s"):format(self.name, self.height, self.opts)
  else
    return ("%s:h%d"):format(self.name, self.height)
  end
end

--- Set font height
function current_font:set()
  vim.o.guifont = tostring(self)
end

--- Increase height by N pts
--- @param by? number
function current_font:dec_height(by)
  by = by or 1
  self.height = self.height - 1
  self:set()
end

--- Decrease height by N pts
--- @param by? number
function current_font:inc_height(by)
  by = by or 1
  self.height = self.height + 1
  self:set()
end

vim.keymap.set("n", "<leader>+", function()
  current_font:inc_height(1)
end, { desc = "font height +1" })

vim.keymap.set("n", "<leader>-", function()
  current_font:dec_height(1)
end, { desc = "font height +1" })

current_font()
user.current_font:set()
