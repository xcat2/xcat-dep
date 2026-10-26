module github.com/xcat2/goconserver

go 1.25.0

replace github.com/kr/pty => github.com/creack/pty v1.1.21

require (
	github.com/golang/protobuf v1.5.4
	github.com/gorilla/mux v1.8.1
	github.com/kr/pty v0.0.0-00010101000000-000000000000
	github.com/sirupsen/logrus v1.9.4
	github.com/spf13/cobra v1.10.2
	github.com/spf13/pflag v1.0.10
	golang.org/x/crypto v0.55.0
	golang.org/x/net v0.57.0
	google.golang.org/grpc v1.83.0
	gopkg.in/yaml.v2 v2.4.0
)

require (
	github.com/inconshreveable/mousetrap v1.1.0 // indirect
	golang.org/x/sys v0.47.0 // indirect
	golang.org/x/term v0.45.0 // indirect
	golang.org/x/text v0.41.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20260526163538-3dc84a4a5aaa // indirect
	google.golang.org/protobuf v1.36.11 // indirect
)
