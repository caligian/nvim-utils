require "nvim-utils.state"
require 'nvim-utils.Autocmd'

--- Create a template instance for file patterns
--- @class Template
--- @overload fun(pat: string|string[], event?: string|string[]): Template
Template = class("Template", {
  static = {
    from_dict = true,
    load_dirs = true,
  },
})

Template.base_dirs =
  { Path.join(user.config_dir, "templates") }

user.templates = user.templates or {} 

function Template.load_dirs() end

function Template.from_dict(specs) end

function Template:set_in_buf(buf)
  throw.missing_templates(#(self.templates) ~= 0)

  local templs = self.templates
  local templs_len = #templs
  local buflc = Buffer.linecount(buf)

  if buflc == 0 then
    Buffer.set(buf, {0, 0}, templs)
    return true
  end

  local lines =  Buffer.lines(buf)
  lines = list.sub(lines, 1, templs_len)

  if case.eq(lines, templs) then
    return
  end

  Buffer.set(buf, {0, 0}, templs)
  return true
end

function Template:is_enabled()
  if self.autocmd and self.autocmd:exists() then
    return
  end
end

function Template:enable()
  if self:is_enabled() then
    return
  end

  local pat = self.pattern
  local event = self.event
  local name = 'template.' .. pat
  local function add_buf(buf)
    if self:set_in_buf(buf) then
      self.buffers[buf] = true
    end
  end

  if not event then
    event = 'BufAdd'
    self.autocmd = Autocmd(event, {pattern = '*', callback = function (bufopts)
      if self.buffers[bufopts.buf] then
        return
      end
      local bufname = nvim.buf.get_name(bufopts.buf)
      if bufname:match(self.pattern)  then
        add_buf(bufopts.buf)
      end
    end, name = name})
  else
    self.autocmd = Autocmd(event, {
      pattern = pat,
      callback = function (bufopts)
        add_buf(bufopts.buf)
      end,
      name = name,
    })
  end

  user.templates[pat] = self
  return self
end

--- @param pat string autocmd pattern, by default use lua pattern[s] with BufAdd
--- @param event? string if nil then use BufAdd with lua pattern matching else use pattern with event
--- @return Template
function Template:init(pat, event, opts)
  form.string.pattern(pat)

  if user.templates[self.pat] then
    return 
  end

  if event then
    form.string.event(event)
  end

  self.templates = {}
  self.pattern = pat
  self.event = event
  self.buffers = {} 

  return self
end

function Template:add(s)
  form[union('string', case.rules.list_of 'string')].s(s)
  if is_string(s) then
    list.append(self.templates, s)
  else
    list.extend(self.templates, s)
  end
end

function Template:from_dict()
end

ex = Template( 'c', 'Filetype')
ex:add "#include <stdio.h>"
ex:enable()
