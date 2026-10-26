package tunnelycore

import (
	"os"
	"path/filepath"
	"testing"
)

// Validates configs produced by the Dart generator (vpn_client test
// "writes golden config for Go validation") with the real Mihomo parser.
func TestGeneratedConfigsAreValid(t *testing.T) {
	home := t.TempDir()
	rules := filepath.Join(home, "ruleset")
	if err := os.MkdirAll(rules, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{"ru-domains.mrs", "ru-ips.mrs"} {
		b, err := os.ReadFile(filepath.Join("..", "..", "vpn_client", "assets", "ruleset", f))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(rules, f), b, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	SetHomeDir(home)

	for _, name := range []string{"generated_ruDirect.json", "generated_global.json"} {
		b, err := os.ReadFile(filepath.Join("testdata", name))
		if err != nil {
			t.Fatalf("%s: %v (run the Flutter tests first)", name, err)
		}
		if msg := Validate(string(b)); msg != "" {
			t.Errorf("%s rejected by Mihomo: %s", name, msg)
		}
	}
}

func TestValidateRejectsGarbage(t *testing.T) {
	if Validate("proxies: [") == "" {
		t.Fatal("expected parse error")
	}
}

func TestValidateRejectsBadProxy(t *testing.T) {
	cfg := `{"proxies":[{"name":"x","type":"vless","server":"a.example.com","port":443,"uuid":"u","reality-opts":{"short-id":"zz"}}],` +
		`"proxy-groups":[{"name":"PROXY","type":"select","proxies":["missing"]}],"rules":["MATCH,PROXY"]}`
	if Validate(cfg) == "" {
		t.Fatal("expected Mihomo to reject a group referencing an unknown proxy")
	}
}
