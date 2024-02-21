Template = class('Template', {
  static = { 'load_config', 'from_dict', }
})

user.templates = user.templates or {}
user.templates_path = user.templates_path or Path.join(user.config_dir, 'lua', 'core', 'templates') 

function Template:init(opts)
  local spec = union('string', 'method', 'table')
  form[{
    opt_filetype = 'string',
    opt_ft = 'string',
    opt_event = spec,
    opt_exclude = spec,
    opt_include = spec,
    pattern = spec,
    put = union('string', case.rules.list_of 'string'),
  }].template(opts)

  local ft = opts.ft or opts.filetype
  local event = tolist(event or 'BufEnter')
  local pattern = tolist(opts.pattern)
  local exclude = tolist(opts.exclude or {})
  local put = tolist(opts.put)
  local include = tolist(opts.include or {})

  if not list.contains(event, 'Filetype') and ft then
    event[#event+1] = 'Filetype'
    pattern[#pattern+1] = ft
  end

  if #put[#put] ~= 0 then
    put[#put+1] = ""
  end

  self.pattern = pattern
  self.event = event
  self.exclude = exclude
  self.attached = {}
  self.put = put
  self.include = include
  self.filetype = ft
  self.autocmd = false

  return self
end

function Template:_add_buffer(buf)
  if not Buffer.exists(buf) or self.attached[buf] then
    return false
  end

  local include =  self.include
  local exclude = self.exclude
  local bufnr = buf
  buf = Buffer.get_name(buf)

  for i = 1, #exclude do
    local p = exclude[i]
    local test = is_method(p) and p(buf) or is_string(p) and buf:match(p)
    if test then
      return false
    end
  end

  for i=1, #include do
    local p = include[i]
    local test = is_method(p) and p(buf) or is_string(p) and buf:match(p)
    if test then
      self.attached[bufnr] = true
      self.attached[buf] = true
      return true
    end
  end
end

function Template:_set(buf)
  if self.attached[buf] or not Buffer.exists(buf) then
    return
  end

  local put = self.put
  local putlc = #put
  local buflc = Buffer.linecount(buf)

  if buflc == 0 then
    Buffer.set(buf, {0, -1}, put)
  end

  local lines = Buffer.lines(buf, 0, putlc)
  if case.eq(lines, put) then
    return
  end

  Buffer.set(buf, {0, 0}, put)
  self:_add_buffer(buf)

  return self
end

function Template:enable()
  if self.autocmd and self.autocmd:exists() then
    return
  end

  self.autocmd = Autocmd(self.event, {
    pattern = self.pattern,
    callback = function (bufopts)
      if self.attached[bufopts.buf] then return end
      self:_set(bufopts.buf)
    end,
  })

  return self
end

function Template.from_dict(specs)
  return dict.map(specs, function (name, specs)
    local t = Template(specs)
    user.templates[name] = t:enable()
    return t
  end)
end

function Template.load_config(p)
  p = p or user.templates_path
  if not Path.is_dir(p) then
    return
  end

  list.each(Path.ls(p), function (f)
    f = Path.basename(f):gsub('%.lua$', '')
    requirex('core.templates.' .. f, function (templ)
      return Template.from_dict(templ)
    end)
  end)
end

Template.load_config()
