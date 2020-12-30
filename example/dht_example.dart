import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

import 'package:dht/dht.dart';
import 'package:dht/src/kademlia/id.dart';

import 'package:torrent_model/torrent_model.dart';

void main() async {
  // [103, 101, 116, 95, 112, 101, 101, 114, 115]
  // [112, 105, 110, 103]

  // print(String.fromCharCodes([103, 101, 116, 95, 112, 101, 101, 114, 115]));
  // print(String.fromCharCodes([112, 105, 110, 103]));
  // exit(1);
  var torrent = await Torrent.parse('example/sample3.torrent');
  var infohashStr = String.fromCharCodes(torrent.infoHashBuffer);
  var dht = DHT();
  var test = <String>{};
  var newNodeCount = 0;
  dht.announce(infohashStr, 22123);
  dht.onError((code, msg) {
    dev.log('发生错误', error: '[$code]$msg');
  });
  dht.onNewPeer((address, port, token) {
    if (test.add('${address.address}:$port')) {
      dev.log('新加入peer $address : $port ， 已有${test.length} 个peer');
    }
  });

  await dht.bootstrap(udpTimeout: 5, cleanNodeTime: 5 * 60);
  torrent.nodes.forEach((url) async {
    dht.addBootstrapNode(url);
  });

  Future.delayed(Duration(seconds: 20), () {
    dht.stop();
    print(dht);
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
