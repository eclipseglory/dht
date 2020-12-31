## About

Bittorrent DHT by Dart.

Support:
- [BEP 0005 DHT Protocal](https://www.bittorrent.org/beps/bep_0005.html)


## Usage

A simple usage example:

```dart
import 'package:dht/dht.dart';

main() {
  var dht = DHT();
  dht.announce(infohashStr, port);
  await dht.bootstrap();
}
```
The method `announce` can invoke after `DHT` bootstrap. But I suggest that invoking it before DHT startted;

Onece `DHT` startted , it will check if there is ant `announce` , if it has , each new DHT node added , it will try to announce the local peer to the new node. 

Before send `announce_peer` query , it **should** send `get_peers` query to get the `token` first , so when user invoke `announce` method , it will fire `get_peers` query automatically and return the result. In other word , if user isn't downloading any resource , he will not to `announce` local peer and he dont need any related peers also. However, user can invoke `requestPeers` method to request the peers:

```dart
  dht.requestPeers(infoHashStr);
```

When `DHT` found any new peer , it will notify the listener:

```dart
  dht.onNewPeer((address, port, infoHash) {
    // found new peer for InfoHash
  });
```

User can add a listener to get `error` from other nodes:
```dart
  dht.onError((code, msg) {
    log('发生错误', error: '[$code]$msg');
  });
```

To stop `DHT` , invoke `stop` method:
```dart
  dht.stop();
```
Once `DHT` stopped , each hanlder will be removed and nothing will be save. If user start `DHT` after it stopped , everything will be fresh.