# Pinned Go module manifest for goconserver

`go.mod` + `go.sum` pin goconserver's Go dependencies so the rpm build is **reproducible without
vendoring the whole dependency tree**. The build runs **inside a mock chroot** (network enabled) and
downloads the modules from the Go proxy at build time; `go.sum` integrity-checks every module, so the
result is deterministic even though the deps are not committed.

- Generated from **xcat2/goconserver @ 6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f** (the pin in
  mockbuild-all.pl / goconserver/mockbuild.pl), with the archived `github.com/kr/pty` replaced by
  `github.com/creack/pty@v1.1.21` and the etcd storage backend removed (xCAT uses file storage only).
- To regenerate after bumping the goconserver pin: clone at the new SHA, remove `storage/etcd*`,
  `go mod init github.com/xcat2/goconserver`,
  `go mod edit -replace github.com/kr/pty=github.com/creack/pty@v1.1.21`, `go mod tidy`, then copy
  go.mod/go.sum here. (No `go mod vendor` needed.)
