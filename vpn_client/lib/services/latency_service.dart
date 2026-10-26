import 'dart:async';
import 'dart:io';

/// TCP connect time to a server, used while the tunnel is down.
/// Returns milliseconds or -1 if unreachable within [timeout].
Future<int> tcpPing(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    socket.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  }
}
