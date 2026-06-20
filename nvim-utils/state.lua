#!/usr/bin/env luajit

if user_config then
  return
end

local root_dir = vim.fn.stdpath('config')
local data_dir = vim.fn.stdpath('data')
local lua_dir = root_dir .. '/lua'
local config_dir = lua_dir .. '/config'
local plugins_dir = config_dir .. '/plugins'
local filetype_dir = config_dir .. '/filetype'
local keymap_file = config_dir .. '/keymap.lua'
local autocmd_file = config_dir .. '/autocmd.lua'
local template_dir = root_dir .. '/templates'
local settings_file = root_dir .. '/settings.lua'

user_config = bless {
  keymap = {}, augroup = {}, autocmd = {}, filetype = {},
  buffer = { buffer_group = {}, recent = {} }, buffer_group = {},
  workspace = {}, project = {}, terminal = {},
  repl = { repl = {}, shell = {}, sh = false },
  path = { file = {}, dir = {}, project = {} },
  telescope = {
    theme = 'ivy', disable_devicons = true,
    previewer = false, layout_config = { height = 13 }
  },
  shell = vim.env.shell,
  utils = { path = {} },
  template = {
    perl = {
      {
        '[.]p[ml]$',
        {
          "#!usr/bin/env perl",
          "",
          "use v5.40;",
          "use strict;",
          "use warnings;",
          "",
        }
      },
    },
    python = {
      {
        '.+%.py$',
        {
          "#!/usr/bin/env python",
          "",
          "import os",
          "import sys",
          '# from argparse import ArgumentParser',
          '# from termcolor import cprint',
          '# from subprocess import run as process, check_output as system',
          "",
          "",
        }
      },
    },
    lua = {
      {
        '/nvim%-utils/.+%.lua$',
        {
          "#!/usr/bin/env luajit",
          "",
          "local lutils = require 'lua-utils'",
          "require 'nvim-utils'",
          "",
        }
      },
    },
    sh = {
      {
        '%.sh$',
        {
          '#!/usr/bin/env bash',
          "",
        }
      }
    },
    tex = {
      {
        '%.tex$',
        {
          "\\documentclass[a4paper,11pt]{report}",
          "% \\documentclass[a4paper,12pt]{report}",
          "",
          "\\usepackage[utf8]{inputenc}",
          "",
          "% Increase paragraph spacing",
          "\\usepackage[skip=12pt]{parskip}",
          "",
          "% Table stuff",
          "\\usepackage{longtable}",
          "\\usepackage{array}",
          "\\usepackage{colortbl}",
          "\\usepackage{tabularx}",
          "",
          "% Math stuff",
          "\\usepackage{amsmath}",
          "\\usepackage{amssymb}",
          "",
          "% Other utility packages",
          "\\usepackage{bookmark}",
          "\\usepackage{ragged2e}",
          "\\usepackage{xurl}",
          "\\usepackage{lscape}",
          "\\usepackage{booktabs}",
          "\\usepackage{graphicx}",
          "\\usepackage{enumitem}",
          "\\usepackage{xcolor}",
          "\\usepackage{rotating}",
          "\\usepackage{hyperref}",
          "\\usepackage{xurl}",
          "\\usepackage{ulem}",
          "",
          "% Bibliography stuff, enable if needed",
          "% \\usepackage[backend=biber,style=authoryear,sorting=nyt]{biblatex}",
          "",
          "% Set margins",
          "\\usepackage[left=1cm,right=1.5cm,top=1.5cm,bottom=1.5cm]{geometry}",
          "",
          "% Your bibliography file",
          "%% \\addbibresource{REFERENCE_FILE}",
          "",
          "%% Additional row height for tables (looks better)",
          "% \\renewcommand*{\\arraystretch}{1.1}",
          "",
          "% Mandatory for prevent blue colored references",
          "\\hypersetup{colorlinks = true, urlcolor = blue, linkcolor = blue, citecolor = red}",
          "",
          "% Add your custom font sizes here",
          "%% \\newcommand{\\HUGE}{\\fontsize{40}{48}\\selectfont}",
          "",
          "\\begin{document}",
          "\\setlength{\\extrarowheight}{3pt}",
          "",
          "\\begin{titlepage}",
          "    \\begin{center}",
          "        \\vspace*{8cm}",
          "        \\Huge{TITLE} \\\\",
          "        \\vspace{0.4cm}",
          "        \\Large{SUBTITLE1} \\\\",
          "        \\vspace*{0.4cm}",
          "        \\large{SUBTITLE2} \\\\",
          "        \\vspace*{0.4cm}",
          "        \\small{AUTHOR} \\\\",
          "    \\end{center}",
          "\\end{titlepage}",
          "",
          "\\tableofcontents",
          "\\newpage",
          "",
          "\\section{Bibliography}{",
          "    % \\addbibliography",
          "}",
          "",
          "\\end{document}",
        }
      }
    }
  }
}

user_config.path = {
  root_dir = root_dir,
  data_dir = data_dir,
  lua_dir = lua_dir,
  config_dir = config_dir,
  filetype_dir = filetype_dir,
  template_dir = template_dir,
  keymap_file = keymap_file,
  autocmd_file = autocmd_file,
  settings_file = settings_file,
  plugins_dir = plugins_dir,
}

user_config.path.file = {
  keymap = keymap_file,
  autocmd = autocmd_file,
  settings = settings_file,
}

user_config.path.dir = {
  root = root_dir,
  data = data_dir,
  lua = lua_dir,
  config = config_dir,
  filetype = filetype_dir,
  template = template_dir,
  plugins = plugins_dir,
}

return user_config
