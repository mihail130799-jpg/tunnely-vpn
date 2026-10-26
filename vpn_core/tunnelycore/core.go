// Package tunnelycore is the gomobile-facing wrapper around the Mihomo core.
//
// Only gomobile-compatible types cross this boundary: string, bool, int32,
// int64, []byte, pointers to structs with such fields, and interfaces.
// The Android/iOS side owns the TUN device and passes its file descriptor
// inside the generated Mihomo YAML (tun.file-descriptor).
package tunnelycore

import (
	"context"
	"errors"
	"sync"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/dialer"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

// Protector excludes a socket from the VPN (Android VpnService.protect).
type Protector interface {
	Protect(fd int32) bool
}

// LogSink receives core log lines. Implementations must not block.
type LogSink interface {
	Log(level string, message string)
}

// Traffic is a snapshot of tunnel throughput in bytes.
type Traffic struct {
	Up        int64 // bytes/s
	Down      int64 // bytes/s
	TotalUp   int64
	TotalDown int64
}

var (
	mu      sync.Mutex
	running bool
	logSub  observable.Subscription[log.Event]
)

// Version returns the embedded Mihomo version.
func Version() string { return C.Version }

// SetHomeDir sets the directory for geo databases, caches and providers.
func SetHomeDir(dir string) { C.SetHomeDir(dir) }

// SetProtector installs a socket hook so outbound sockets bypass the TUN.
// Pass nil to remove it.
func SetProtector(p Protector) {
	if p == nil {
		dialer.DefaultSocketHook = nil
		return
	}
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		var protectErr error
		err := conn.Control(func(fd uintptr) {
			if !p.Protect(int32(fd)) {
				protectErr = errors.New("protect socket failed")
			}
		})
		if err != nil {
			return err
		}
		return protectErr
	}
}

// SetLogSink streams core logs to sink. Pass nil to stop streaming.
func SetLogSink(sink LogSink) {
	mu.Lock()
	defer mu.Unlock()
	if logSub != nil {
		log.UnSubscribe(logSub)
		logSub = nil
	}
	if sink == nil {
		return
	}
	sub := log.Subscribe()
	logSub = sub
	go func() {
		for e := range sub {
			sink.Log(e.LogLevel.String(), e.Payload)
		}
	}()
}

// Validate parses a config without applying it. Returns "" when valid.
func Validate(configYAML string) string {
	if _, err := executor.ParseWithBytes([]byte(configYAML)); err != nil {
		return err.Error()
	}
	return ""
}

// Start parses and applies the config, bringing up the TUN listener.
// Calling Start while running reapplies the new config.
func Start(configYAML string) error {
	mu.Lock()
	defer mu.Unlock()
	cfg, err := executor.ParseWithBytes([]byte(configYAML))
	if err != nil {
		return err
	}
	hub.ApplyConfig(cfg)
	running = true
	return nil
}

// Stop tears down listeners (including TUN) and closes active connections.
func Stop() {
	mu.Lock()
	defer mu.Unlock()
	if !running {
		return
	}
	executor.Shutdown()
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
	statistic.DefaultManager.ResetStatistic()
	running = false
}

// IsRunning reports whether Start succeeded and Stop has not been called.
func IsRunning() bool {
	mu.Lock()
	defer mu.Unlock()
	return running
}

// TrafficNow returns current speed and totals since Start.
func TrafficNow() *Traffic {
	up, down := statistic.DefaultManager.Now()
	tu, td := statistic.DefaultManager.Total()
	return &Traffic{Up: up, Down: down, TotalUp: tu, TotalDown: td}
}

// Delay measures latency through the named proxy in milliseconds.
// Returns -1 on failure or timeout.
func Delay(proxyName string, testURL string, timeoutMs int32) int64 {
	proxy, ok := tunnel.Proxies()[proxyName]
	if !ok {
		return -1
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
	defer cancel()
	d, err := proxy.URLTest(ctx, testURL, utils.IntRanges[uint16]{})
	if err != nil {
		return -1
	}
	return int64(d)
}

// SelectProxy switches a select-type group to the named proxy.
func SelectProxy(group string, name string) bool {
	p, ok := tunnel.Proxies()[group]
	if !ok {
		return false
	}
	sel, ok := p.Adapter().(outboundgroup.SelectAble)
	if !ok {
		return false
	}
	return sel.Set(name) == nil
}

// NowProxy returns the currently selected member of a group, or "".
func NowProxy(group string) string {
	p, ok := tunnel.Proxies()[group]
	if !ok {
		return ""
	}
	if g, ok := p.Adapter().(outboundgroup.ProxyGroup); ok {
		return g.Now()
	}
	return ""
}
