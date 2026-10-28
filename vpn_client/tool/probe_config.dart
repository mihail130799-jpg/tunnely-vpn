// Dev tool: prints the probe config (outbounds only) for links in a file.
// Usage: dart run tool/probe_config.dart <links.txt>
import 'dart:io';

import 'package:tunnely/core/subscription_parser.dart';
import 'package:tunnely/core/xray_config.dart';
import 'package:tunnely/models/server_profile.dart';

void main(List<String> args) {
  final batch = parseBatch(File(args.first).readAsStringSync());
  final servers = [
    for (var i = 0; i < batch.proxies.length; i++) ServerProfile(id: '$i', proxy: batch.proxies[i]),
  ];
  stdout.write(buildProbeConfig(servers));
  stderr.writeln(servers.map((s) => '${outboundTagFor(s)}=${s.name}').join(', '));
}
