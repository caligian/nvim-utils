local text = {}

text.autocmds = {
  set_autowrap = function(opts)
    nvim.buf.create_user_command(opts.buf, "EnableAutowrap", function(opts)
      local buf = opts.buf

      print("enabling autowrap for " .. Buffer.name(buf))

      Buffer.set_option(buf, "formatoptions", "tqwan1p")
      Buffer.set_option(buf, "textwidth", 80)
    end, {})
  end,
}

return text
