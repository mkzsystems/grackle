package cli

import (
	"bytes"
	"errors"
	"fmt"
	"runtime"
	"strings"
	"testing"

	"github.com/spf13/cobra"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name       string
		version    string
		args       []string
		wantCode   int
		wantStdout string
		wantStderr string
	}{
		{name: "version from ldflags", version: "v1.2.3", args: []string{"version"},
			wantStdout: "grackle v1.2.3 " + runtime.GOOS + "/" + runtime.GOARCH + " " + runtime.Version() + "\n"},
		{name: "version takes no arguments", version: "v1.2.3", args: []string{"version", "extra"}, wantCode: 1,
			wantStderr: "grackle: unknown command"},
		{name: "unknown command", version: "v1.2.3", args: []string{"nope"}, wantCode: 1,
			wantStderr: `grackle: unknown command "nope"`},
		{name: "no arguments prints help", version: "v1.2.3", args: nil, wantStdout: "Usage:"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			code := Run(tt.version, tt.args, &stdout, &stderr)
			if code != tt.wantCode {
				t.Errorf("exit code = %d, want %d (stderr %q)", code, tt.wantCode, stderr.String())
			}
			if tt.wantStdout != "" && !strings.Contains(stdout.String(), tt.wantStdout) {
				t.Errorf("stdout = %q, want it to contain %q", stdout.String(), tt.wantStdout)
			}
			if tt.wantStderr != "" && !strings.Contains(stderr.String(), tt.wantStderr) {
				t.Errorf("stderr = %q, want it to contain %q", stderr.String(), tt.wantStderr)
			}
		})
	}
}

func TestResolveVersion(t *testing.T) {
	if got := resolveVersion("v0.1.0"); got != "v0.1.0" {
		t.Errorf("resolveVersion(v0.1.0) = %q", got)
	}
	// A test binary records no module version, so the fallback ends at "dev".
	for _, in := range []string{"", "dev"} {
		if got := resolveVersion(in); got != "dev" {
			t.Errorf("resolveVersion(%q) = %q, want dev", in, got)
		}
	}
}

func TestExecuteExitCodes(t *testing.T) {
	tests := []struct {
		name     string
		err      error
		wantCode int
	}{
		{"success", nil, 0},
		{"plain error", errors.New("boom"), 1},
		{"exit error", &exitError{code: 2, err: errors.New("quota exhausted")}, 2},
		{"wrapped exit error", fmt.Errorf("sync: %w", &exitError{code: 2, err: errors.New("quota exhausted")}), 2},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			root := newRoot("v0")
			root.AddCommand(&cobra.Command{Use: "probe", RunE: func(*cobra.Command, []string) error { return tt.err }})
			var stdout, stderr bytes.Buffer
			if code := execute(root, []string{"probe"}, &stdout, &stderr); code != tt.wantCode {
				t.Errorf("exit code = %d, want %d", code, tt.wantCode)
			}
			if tt.err != nil && !strings.Contains(stderr.String(), "grackle: "+tt.err.Error()) {
				t.Errorf("stderr = %q, want the error message", stderr.String())
			}
		})
	}
}
