package tunnelycore

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Loads the configs produced by the Dart generator (vpn_client test
// "writes golden configs for Go validation") with the real Xray config
// loader and builds instances from them (without starting the tun).
func TestGeneratedConfigsLoad(t *testing.T) {
	files, _ := filepath.Glob(filepath.Join("testdata", "xray_*.json"))
	if len(files) == 0 {
		t.Fatal("no golden configs: run the Flutter tests first")
	}
	for _, f := range files {
		b, err := os.ReadFile(f)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := load(string(b)); err != nil {
			t.Errorf("%s rejected by Xray loader: %v", filepath.Base(f), err)
		}
	}
	b, _ := os.ReadFile(filepath.Join("testdata", "xray_probe.json"))
	if msg := Validate(string(b)); msg != "" {
		t.Errorf("probe config: %s", msg)
	}
}

func TestValidateRejectsGarbage(t *testing.T) {
	if Validate(`{"outbounds": [`) == "" {
		t.Fatal("expected parse error")
	}
	if Validate(`{"outbounds":[{"protocol":"vless","settings":{"vnext":[]}}]}`) == "" {
		t.Fatal("expected Xray to reject a vless outbound without servers")
	}
}

// Live check against real servers: set TUNNELY_LIVE_PROBE to a probe config
// (outbounds only) and TUNNELY_LIVE_TAGS to a comma-separated list of tags.
func TestLiveProbe(t *testing.T) {
	path, tags := os.Getenv("TUNNELY_LIVE_PROBE"), os.Getenv("TUNNELY_LIVE_TAGS")
	if path == "" || tags == "" {
		t.Skip("TUNNELY_LIVE_PROBE / TUNNELY_LIVE_TAGS not set")
	}
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	for _, tag := range strings.Split(tags, ",") {
		t.Logf("%s: %s", tag, DelayError(tag, "https://www.gstatic.com/generate_204", 8000, string(b)))
	}
}

func TestEventLogAndLogFileRouting(t *testing.T) {
	SetHomeDir(t.TempDir())
	defer SetHomeDir("")
	AppendEvent("service: start requested")
	AppendEvent("core: started")
	ev := RecentEvents()
	if !strings.Contains(ev, "service: start requested") || !strings.Contains(ev, "core: started") {
		t.Fatalf("events not recorded: %q", ev)
	}
	cfg := withLogFile(`{"log":{"loglevel":"warning"},"outbounds":[]}`)
	if !strings.Contains(cfg, "core.log") || !strings.Contains(cfg, `"loglevel":"warning"`) {
		t.Fatalf("log file not injected: %s", cfg)
	}
	ClearLogs()
	if RecentEvents() != "" {
		t.Fatal("ClearLogs did not clear events")
	}
}
