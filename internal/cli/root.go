// Package cli wires grackle's commands. Each command lives in its own file; cmd/grackle only
// calls Run.
package cli

import (
	"errors"
	"fmt"
	"io"
	"runtime/debug"

	"github.com/spf13/cobra"
)

// exitError carries a specific exit code out of a command. Commands return one when the code
// matters (docs/plan.md section 3.7); any other error exits 1.
type exitError struct {
	code int
	err  error
}

func (e *exitError) Error() string { return e.err.Error() }
func (e *exitError) Unwrap() error { return e.err }

// Run executes the command line in args and returns the process exit code.
func Run(version string, args []string, stdout, stderr io.Writer) int {
	return execute(newRoot(resolveVersion(version)), args, stdout, stderr)
}

// execute runs root and maps its error to an exit code.
func execute(root *cobra.Command, args []string, stdout, stderr io.Writer) int {
	root.SetArgs(args)
	root.SetOut(stdout)
	root.SetErr(stderr)
	if err := root.Execute(); err != nil {
		fmt.Fprintln(stderr, "grackle:", err)
		var ee *exitError
		if errors.As(err, &ee) {
			return ee.code
		}
		return 1
	}
	return 0
}

func newRoot(version string) *cobra.Command {
	root := &cobra.Command{
		Use:           "grackle",
		Short:         "A control tower for projects spread across many GitHub orgs and repos",
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	root.AddCommand(newVersionCmd(version))
	return root
}

// resolveVersion prefers the ldflags version; a plain `go install …@vX` build has none, so it
// falls back to the module version Go recorded in the binary.
func resolveVersion(ldflags string) string {
	if ldflags != "" && ldflags != "dev" {
		return ldflags
	}
	if bi, ok := debug.ReadBuildInfo(); ok && bi.Main.Version != "" && bi.Main.Version != "(devel)" {
		return bi.Main.Version
	}
	return "dev"
}
