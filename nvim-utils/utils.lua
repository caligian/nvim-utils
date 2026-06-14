require 'lua-utils.dump'
local utils = {}

---@param prefix string?
---@param msg string
---@param ...
---@return string
function utils.msg_with_prefix(prefix, msg, ...)
  prefix = prefix or '<root>'
  msg = prefix .. '.' .. msg

  return sprintf(msg, ...)
end

function utils.msg(msg, ...)
  return sprintf(msg, ...)
end

---@param prefix string?
---@param msg string
---@param ...
---@return string
function utils.err_with_prefix(prefix, msg, ...)
  prefix = prefix or '<root>'
  msg = prefix .. '.' .. msg

  return sprintf(msg, ...)
end

function utils.err(msg, ...)
  return errorf(msg, ...)
end

return utils
