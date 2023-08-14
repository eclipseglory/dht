import 'dart:developer' as dev;
import 'package:dtorrent_common/dtorrent_common.dart';

import 'package:bittorrent_dht/bittorrent_dht.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';

void main() async {
  var torrent = await Torrent.parse('example/test7.torrent');
  var infohashStr = String.fromCharCodes(torrent.infoHashBuffer);
  var dht = DHT();
  var test = <CompactAddress>{};
  dht.announce(infohashStr, 22123);
  dht.onError((code, msg) {
    dev.log('Error happend:', error: '[$code]$msg');
  });
  dht.onNewPeer((peer, token) {
    if (test.add(peer)) {
      dev.log(
          'Found new peer address : $peer  ， Have ${test.length} peers already');
    }
  });

  await dht.bootstrap(udpTimeout: 5, cleanNodeTime: 5 * 60);
  for (var url in torrent.nodes) {
    await dht.addBootstrapNode(url);
  }

  Future.delayed(Duration(seconds: 10), () {
    dht.stop();
  });
}

String intToRadix2String(int element) {
  var s = element.toRadixString(2);
  if (s.length != 8) {
    var l = s.length;
    for (var i = 0; i < 8 - l; i++) {
      s = '${0}$s';
    }
  }
  return s;
}
