// Package tunnelycore is the gomobile-facing wrapper around Xray-core.
//
// Only gomobile-compatible types cross this boundary: string, bool, int32,
// int64, []byte, pointers to structs with such fields, and interfaces.
// The Android side owns the TUN device; its fd is handed to Xray's tun
// inbound through the "xray.tun.fd" environment flag.
package tunnelycore

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	xnet "github.com/xtls/xray-core/common/net"
	"github.com/xtls/xray-core/common/platform"
	"github.com/xtls/xray-core/common/session"
	"github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/transport/internet"

	// Registers every Xray feature and the JSON config loader.
	_ "github.com/xtls/xray-core/main/distro/all"
)

// TunInboundTag must match the tun inbound tag in the generated config.
const TunInboundTag = "tun-in"

// Protector excludes a socket from the VPN (Android VpnService.protect).
type Protector interface {
	Protect(fd int32) bool
}

// Traffic is a snapshot of tunnel throughput in bytes.
type Traffic struct {
	Up        int64 // bytes/s
	Down      int64 // bytes/s
	TotalUp   int64
	TotalDown int64
}

var (
	mu       sync.Mutex
	instance *core.Instance
	homeDir  string

	trafficMu   sync.Mutex
	lastUp      int64
	lastDown    int64
	lastSampled time.Time

	protectorMu sync.RWMutex
	protector   Protector
)

func init() {
	// Outbound sockets must bypass the VPN; the controller is registered once
	// and consults whatever protector is current.
	_ = internet.RegisterDialerController(func(network, address string, c syscall.RawConn) error {
		protectorMu.RLock()
		p := protector
		protectorMu.RUnlock()
		if p == nil {
			return nil
		}
		var protectErr error
		if err := c.Control(func(fd uintptr) {
			if !p.Protect(int32(fd)) {
				protectErr = errors.New("protect socket failed")
			}
		}); err != nil {
			return err
		}
		return protectErr
	})
}

// Version returns the embedded Xray-core version.
func Version() string { return core.Version() }

// SetHomeDir sets the asset directory (geo files) for Xray.
func SetHomeDir(dir string) {
	homeDir = dir
	_ = os.Setenv("xray.location.asset", dir)
}

// SetProtector installs the socket protector. Pass nil to remove it.
func SetProtector(p Protector) {
	protectorMu.Lock()
	protector = p
	protectorMu.Unlock()
}

func load(configJSON string) (*core.Config, error) {
	return core.LoadConfig("json", strings.NewReader(configJSON))
}

// Validate parses and builds a config without starting it. Returns "" when valid.
func Validate(configJSON string) string {
	cfg, err := load(configJSON)
	if err != nil {
		return err.Error()
	}
	inst, err := core.New(cfg)
	if err != nil {
		return err.Error()
	}
	_ = inst.Close()
	return ""
}

// StartWithFd starts Xray with the tun inbound reading from tunFd.
// A running instance is replaced.
func StartWithFd(configJSON string, tunFd int32) error {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
	_ = os.Setenv(platform.TunFdKey, strconv.Itoa(int(tunFd)))
	configJSON = withLogFile(configJSON)
	AppendEvent("core: starting Xray " + core.Version())
	cfg, err := load(configJSON)
	if err != nil {
		return err
	}
	inst, err := core.New(cfg)
	if err != nil {
		return err
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		AppendEvent("core: start failed: " + err.Error())
		return err
	}
	instance = inst
	resetTraffic()
	AppendEvent("core: started")
	return nil
}

func stopLocked() {
	if instance != nil {
		_ = instance.Close()
		instance = nil
		AppendEvent("core: stopped")
	}
}

// Stop shuts the running instance down (closing its sockets and the tun reader).
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	stopLocked()
}

// IsRunning reports whether an instance is active.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return instance != nil
}

// CloseAllConnections is kept for API compatibility; Xray connections fail
// over by themselves when the underlying network changes.
func CloseAllConnections() {}

// counterVisitor is implemented by Xray's stats manager.
type counterVisitor interface {
	VisitCounters(func(string, stats.Counter) bool)
}

// totals sums traffic of every outbound (proxies and direct). The tun inbound
// alone undercounts, outbound counters see all bytes that leave the device.
func totals(m stats.Manager) (up, down int64) {
	v, ok := m.(counterVisitor)
	if !ok {
		return 0, 0
	}
	v.VisitCounters(func(name string, c stats.Counter) bool {
		if strings.HasPrefix(name, "outbound>>>") && !strings.HasPrefix(name, "outbound>>>dns-out>>>") {
			switch {
			case strings.HasSuffix(name, ">>>uplink"):
				up += c.Value()
			case strings.HasSuffix(name, ">>>downlink"):
				down += c.Value()
			}
		}
		return true
	})
	return up, down
}

func resetTraffic() {
	trafficMu.Lock()
	lastUp, lastDown, lastSampled = 0, 0, time.Now()
	trafficMu.Unlock()
}

// TrafficNow returns the current speed (since the previous call) and totals.
func TrafficNow() *Traffic {
	mu.Lock()
	inst := instance
	mu.Unlock()
	if inst == nil {
		return &Traffic{}
	}
	m, ok := inst.GetFeature(stats.ManagerType()).(stats.Manager)
	if !ok || m == nil {
		return &Traffic{}
	}
	up, down := totals(m)

	trafficMu.Lock()
	defer trafficMu.Unlock()
	now := time.Now()
	t := &Traffic{TotalUp: up, TotalDown: down}
	if secs := now.Sub(lastSampled).Seconds(); secs > 0.2 {
		t.Up = int64(float64(up-lastUp) / secs)
		t.Down = int64(float64(down-lastDown) / secs)
		lastUp, lastDown, lastSampled = up, down, now
	}
	return t
}

// Delay measures an HTTP round trip through the outbound with the given tag,
// in milliseconds; -1 on failure. Works while connected (uses the running
// instance) and while disconnected (builds a temporary one from configJSON).
func Delay(outboundTag string, testURL string, timeoutMs int32, configJSON string) int64 {
	ms, _ := measure(outboundTag, testURL, timeoutMs, configJSON)
	return ms
}

// DelayError is Delay that also returns the failure reason (empty on success),
// formatted as "<ms>|<error>".
func DelayError(outboundTag string, testURL string, timeoutMs int32, configJSON string) string {
	ms, err := measure(outboundTag, testURL, timeoutMs, configJSON)
	if err != nil {
		return fmt.Sprintf("%d|%s", ms, err.Error())
	}
	return fmt.Sprintf("%d|", ms)
}

func measure(outboundTag, testURL string, timeoutMs int32, configJSON string) (int64, error) {
	mu.Lock()
	inst := instance
	mu.Unlock()
	if inst == nil {
		if configJSON == "" {
			return -1, errors.New("core is not running")
		}
		cfg, err := load(configJSON)
		if err != nil {
			return -1, err
		}
		tmp, err := core.New(cfg)
		if err != nil {
			return -1, err
		}
		if err := tmp.Start(); err != nil {
			_ = tmp.Close()
			return -1, err
		}
		defer tmp.Close()
		inst = tmp
	}

	timeout := time.Duration(timeoutMs) * time.Millisecond
	client := &http.Client{
		Timeout: timeout,
		Transport: &http.Transport{
			DisableKeepAlives: true,
			DialContext: func(ctx context.Context, network, addr string) (xnet.Conn, error) {
				dest, err := xnet.ParseDestination(network + ":" + addr)
				if err != nil {
					return nil, err
				}
				ctx = session.SetForcedOutboundTagToContext(ctx, outboundTag)
				return core.Dial(ctx, inst, dest)
			},
		},
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, testURL, nil)
	if err != nil {
		return -1, err
	}
	start := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return -1, err
	}
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
	_ = resp.Body.Close()
	if resp.StatusCode >= 500 {
		return -1, fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	return time.Since(start).Milliseconds(), nil
}

// --- logs for in-app diagnostics -------------------------------------------
//
// core.log   — Xray's own error log (level from the config), truncated when large.
// events.log — service/core lifecycle events appended by AppendEvent.
// Both live in homeDir (app-private storage) and never contain keys.

const (
	coreLogName   = "core.log"
	eventsLogName = "events.log"
	maxLogBytes   = 512 << 10
)

var eventsMu sync.Mutex

func logPath(name string) string {
	if homeDir == "" {
		return ""
	}
	return filepath.Join(homeDir, name)
}

// withLogFile points Xray's error log at core.log (truncating it when large).
func withLogFile(configJSON string) string {
	path := logPath(coreLogName)
	if path == "" {
		return configJSON
	}
	if fi, err := os.Stat(path); err == nil && fi.Size() > maxLogBytes {
		_ = os.Truncate(path, 0)
	}
	var m map[string]any
	if err := json.Unmarshal([]byte(configJSON), &m); err != nil {
		return configJSON
	}
	l, _ := m["log"].(map[string]any)
	if l == nil {
		l = map[string]any{}
	}
	l["error"] = path
	l["access"] = "none"
	m["log"] = l
	b, err := json.Marshal(m)
	if err != nil {
		return configJSON
	}
	return string(b)
}

// AppendEvent adds a timestamped line to events.log.
func AppendEvent(line string) {
	path := logPath(eventsLogName)
	if path == "" {
		return
	}
	eventsMu.Lock()
	defer eventsMu.Unlock()
	if fi, err := os.Stat(path); err == nil && fi.Size() > maxLogBytes {
		keepTail(path, 1000)
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(time.Now().Format("2006-01-02 15:04:05 ") + line + "\n")
}

func keepTail(path string, lines int) {
	tail := readTail(path, lines)
	_ = os.WriteFile(path, []byte(tail+"\n"), 0o600)
}

func readTail(path string, lines int) string {
	if path == "" {
		return ""
	}
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	ring := make([]string, 0, lines)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64<<10), 1<<20)
	for sc.Scan() {
		if len(ring) == lines {
			ring = ring[1:]
		}
		ring = append(ring, sc.Text())
	}
	return strings.Join(ring, "\n")
}

// RecentLogs returns the last lines of the Xray core log, oldest first.
func RecentLogs() string { return readTail(logPath(coreLogName), 400) }

// RecentEvents returns the last service/core lifecycle events, oldest first.
func RecentEvents() string { return readTail(logPath(eventsLogName), 400) }

// ClearLogs empties both log files.
func ClearLogs() {
	eventsMu.Lock()
	defer eventsMu.Unlock()
	for _, n := range []string{coreLogName, eventsLogName} {
		if p := logPath(n); p != "" {
			_ = os.Truncate(p, 0)
		}
	}
}
