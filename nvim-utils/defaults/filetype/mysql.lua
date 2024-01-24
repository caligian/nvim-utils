local mysql = {}
mysql.repl = "mysql"
mysql.server = "sqlls"
mysql.formatter = {
  buffer = Path.join(os.getenv "HOME", "node_modules", ".bin", "sql-formatter") .. " --fix",
  stdin = true,
}

return mysql
