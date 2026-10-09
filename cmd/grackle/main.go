// Command grackle syncs issues, pull requests and milestones from GitHub orgs into SQLite and
// serves one board over all of them. See docs/DESIGN.md.
package main

import (
	"os"

	"github.com/mkzsystems/grackle/internal/cli"
)

// version is set at build time with -ldflags "-X main.version=…"; see the Makefile.
var version = "dev"

func main() {
	os.Exit(cli.Run(version, os.Args[1:], os.Stdout, os.Stderr))
}
