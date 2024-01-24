local go = {}

go.server = "gopls"
go.compile = {
  buffer = "go run {path}",
  workspace = "go run {path}",
}
go.test = "go test"
go.formatter = { buffer = "gofmt -s -e {path}" }

return go
