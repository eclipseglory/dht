import 'dart:async';
import 'dart:collection';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dht/src/kademlia/id.dart';
import 'package:dht/src/kademlia/node.dart';
import 'package:dht/src/kademlia/peer_value.dart';
import 'package:dht/src/krpc/krpc.dart';
import 'package:dht/src/krpc/krpc_message.dart';

typedef NewPeerHandler = void Function(
    InternetAddress address, int port, String hashinfo);

class DHT {
  KRPC _krpc;

  Node _root;

  final Map<String, Queue<PeerValue>> _resourceTable =
      <String, Queue<PeerValue>>{};

  final Map<String, int> _announceTable = <String, int>{};

  final Set<NewPeerHandler> _newPeerHandler = <NewPeerHandler>{};

  final Set<void Function(int code, String msg)> _errorHandler =
      <void Function(int code, String msg)>{};

  final List<Uri> _defaultBootstrapNodes = [
    Uri(host: 'router.bittorrent.com', port: 6881),
    Uri(host: 'router.utorrent.com', port: 6881),
    Uri(host: 'dht.transmissionbt.com', port: 6881)
  ];

  final int _maxPeerNum = 7;

  int _cleanNodeTime;

  final _xorToken = Uint8List(4);

  Timer _tokenGenerateTimer;

  int _port;

  int get port => _port;

  Future bootstrap(
      {int cleanNodeTime = 15 * 60,
      int udpTimeout = TIME_OUT_TIME,
      int maxQeury = 24}) async {
    _cleanNodeTime = cleanNodeTime;
    assert(_cleanNodeTime != null && udpTimeout != null && maxQeury != null,
        'incorrect parameters');
    _generateXorToken();
    _tokenGenerateTimer?.cancel();
    _tokenGenerateTimer = Timer.periodic(Duration(minutes: 10), (timer) {
      _generateXorToken();
    });
    var id = ID.randomID();
    _krpc ??= KRPC.newService(id, timeout: udpTimeout, maxQuery: maxQeury);
    _port = await _krpc.start();
    _krpc.onError(_fireError);

    _krpc.onPong(_processPong);
    _krpc.onPing(_processPing);

    _krpc.onFindNodeRequest(_processFindNodeRequest);
    _krpc.onFindNodeResponse(_processFindNodeResponse);

    _krpc.onGetPeersRequest(_processGetPeersRequest);
    _krpc.onGetPeersReponse(_processGetPeersResponse);

    _krpc.onAnnouncePeerRequest(_processAnnouncePeerRequest);
    _krpc.onAnnouncePeerResponse((nodeId, address, port, data) {});
    _root ??= Node(id, PeerValue(InternetAddress.anyIPv4, _krpc.port), -1, 8);
    _root.onBucketEmpty(_allFindNode);
    _defaultBootstrapNodes.forEach((url) {
      addBootstrapNode(url);
    });
    return _port;
  }

  Future stop() async {
    _resourceTable.clear();
    _announceTable.clear();
    _newPeerHandler.clear();
    _errorHandler.clear();
    _tokenGenerateTimer?.cancel();
    _tokenGenerateTimer = null;
    _port = null;
    _root?.dispose();
    _root = null;
    await _krpc?.stop('DHT stopped');
    _krpc = null;
  }

  bool onError(void Function(int code, String msg) h) {
    return _errorHandler.add(h);
  }

  bool offError(void Function(int code, String msg) h) {
    return _errorHandler.remove(h);
  }

  void _fireError(InternetAddress address, int port, int code, String msg) {
    _errorHandler.forEach((handler) {
      Timer.run(() => handler(code, msg));
    });
  }

  bool onNewPeer(NewPeerHandler handler) {
    return _newPeerHandler.add(handler);
  }

  bool offNewPeer(NewPeerHandler handler) {
    return _newPeerHandler.remove(handler);
  }

  void _fireFoundNewPeer(InternetAddress address, int port, String infoHash) {
    _newPeerHandler.forEach((handler) {
      Timer.run(() => handler(address, port, infoHash));
    });
  }

  bool _canAdd(ID id) {
    if (id == _root.id) return false;
    var node = _root.findNode(id);
    if (node == null) {
      var b = _root.getIDBelongBucket(id);
      if (b == null || b.isNotFull) {
        return true;
      }
    }
    return false;
  }

  void _processPong(
      List<int> idBytes, InternetAddress address, int port, dynamic data) {
    var id = ID.createID(idBytes, 0, 20);
    if (_canAdd(id)) {
      _tryToGetNode(address, port);
    } else {
      var node = _root.findNode(id);
      node?.resetCleanupTimer();
    }
  }

  void _processPing(List<int> idBytes, String tid, InternetAddress address,
      int port, dynamic data) {
    var id = ID.createID(idBytes, 0, 20);
    Timer.run(() => _krpc.pong(tid, address, port));
    if (_canAdd(id)) {
      _tryToGetNode(address, port);
    } else {
      var node = _root.findNode(id);
      node?.resetCleanupTimer();
    }
  }

  void _processAnnouncePeerRequest(List<int> idBytes, String tid,
      InternetAddress address, int port, dynamic data) {
    var infoHash = data['info_hash'] as List<int>;
    if (infoHash == null || infoHash.length != 20) {
      _krpc.error(tid, address, port, 203, 'Bad InfoHash');
      return;
    }
    var token = data[TOKEN_KEY];
    if (token == null || token.length != 4 || !_validateToken(token, address)) {
      _krpc.error(tid, address, port, 203, 'Bad token');
      return;
    }
    var infoHashStr = String.fromCharCodes(infoHash);
    _resourceTable[infoHashStr] ??= Queue<PeerValue>();
    var peers = _resourceTable[infoHashStr];
    var peer;
    var implied_port = data['implied_port'];
    if (implied_port != null && implied_port != 0) {
      peer = PeerValue(address, port);
    } else {
      var peerPort = data['port'];
      if (peerPort == null) {
        _krpc.error(
            tid, address, port, 203, 'invalid arguments - port is null');
        return;
      }
      peer = PeerValue(address, peerPort);
    }
    if (peer != null) {
      peers.addLast(peer);
      if (peers.length > _maxPeerNum) {
        peers.removeFirst();
      }
    }
  }

  void _allFindNode(int index) {
    index = 159 - index;
    var id = ID.randomID(20);
    var n = index ~/ 8; //相同数字个数
    var offset = index.remainder(8); // 第一个不相同数字的前面多少bit相同
    var newId = List<int>(20);
    var j = 0;
    for (; j < n; j++) {
      newId[j] = id.getValueAt(j);
    }
    if (j >= id.byteLength) return;
    var fna = id.getValueAt(j);
    var fnb = 0;
    for (var i = 0; i < offset; i++) {
      var base = 128;
      base = base >> i;
      var a = base & fna;
      fnb = fnb | a;
    }
    for (var i = offset; i < 8; i++) {
      var base = 128;
      base = base >> i;
      var a = base & fna;
      if (a == 0) {
        fnb = fnb | base;
      }
    }
    newId[j] = fnb;
    var r = math.Random();
    for (var i = j + 1; i < 20; i++) {
      newId[i] = r.nextInt(256);
    }
    var nid = ID.createID(newId);
    // print('bucket $index 全部清空，查询对应节点 ${nid.toString()}');
    _root?.forEach((node) {
      node.queried = false;
      _tryToGetNode(node.address, node.port, nid.toString());
    });
  }

  bool _validateToken(List<int> token, InternetAddress address) {
    var a = address.rawAddress[0] ^ _xorToken[3];
    var b = address.rawAddress[1] ^ _xorToken[2];
    var c = address.rawAddress[2] ^ _xorToken[1];
    var d = address.rawAddress[3] ^ _xorToken[0];
    return token[0] == a && token[1] == b && token[2] == c && token[3] == d;
  }

  void _generateXorToken() {
    var temp = ID.randomID(4);
    _xorToken[0] = temp.getValueAt(0);
    _xorToken[1] = temp.getValueAt(1);
    _xorToken[2] = temp.getValueAt(2);
    _xorToken[3] = temp.getValueAt(3);
  }

  List<int> _createToken(InternetAddress address) {
    var a = address.rawAddress[0] ^ _xorToken[3];
    var b = address.rawAddress[1] ^ _xorToken[2];
    var c = address.rawAddress[2] ^ _xorToken[1];
    var d = address.rawAddress[3] ^ _xorToken[0];
    return [a, b, c, d];
  }

  void _processGetPeersRequest(List<int> idBytes, String tid,
      InternetAddress address, int port, dynamic data) {
    var qid = ID.createID(idBytes, 0, 20);
    if (_canAdd(qid)) {
      // 不放过任何一个机会
      _tryToGetNode(address, port);
    } else {
      var node = _root.findNode(qid);
      node?.resetCleanupTimer();
    }
    var infohash = data['info_hash'] as List<int>;
    if (infohash == null || infohash.length != 20) {
      _krpc.error(tid, address, port, 203, 'invalid arguments');
      return;
    }
    var nodes = _findClosestNode(infohash);
    var infoHashStr = String.fromCharCodes(infohash);
    var peers = _resourceTable[infoHashStr];
    var token = String.fromCharCodes(_createToken(address));
    // 这里要返回Peers
    _krpc.responseGetPeers(tid, infoHashStr, address, port, token,
        nodes: nodes, peers: peers);
  }

  void _processGetPeersResponse(
      List<int> idBytes, InternetAddress address, int port, dynamic data) {
    var qid = ID.createID(idBytes, 0, 20);
    var node = _root.findNode(qid);
    if (node == null) return;
    node.resetCleanupTimer();
    var token = String.fromCharCodes(data['token']);
    if (token == null) {
      log('Response Error',
          error: 'Dont include Token', name: runtimeType.toString());
      return;
    }
    var infoHash = data['__additional'];
    if (infoHash == null) {
      log('Inner Error',
          error: 'InfoHash didn\'t record', name: runtimeType.toString());
      return;
    }
    // 如果没有宣布，就宣布一次
    if (node.announced[infoHash] == null || !node.announced[infoHash]) {
      node.token[infoHash] = token;
      var peerPort = _announceTable[infoHash];
      if (peerPort != null) {
        node.announced[infoHash] = true;
        // print('公告Peer:端口 $peerPort ,hash:$infoHash');
        _krpc.announcePeer(infoHash, peerPort, token, address, port);
      }
    }
    if (data[NODES_KEY] != null) {
      _processFindNodeResponse(idBytes, address, port, data);
    }
    if (data[VALUES_KEY] != null) {
      var peers = data[VALUES_KEY];
      peers.forEach((peer) {
        try {
          var p = PeerValue.parse(peer);
          if (p != null) {
            _fireFoundNewPeer(p.address, p.port, infoHash);
          }
        } catch (e) {
          // do nothing
          log('Parse peer address error:',
              error: e, name: runtimeType.toString());
        }
      });
    }
  }

  void _processFindNodeRequest(List<int> idBytes, String tid,
      InternetAddress address, int port, dynamic data) {
    var qid = ID.createID(idBytes, 0, 20);
    if (_canAdd(qid)) {
      // 不放过任何一个机会
      _tryToGetNode(address, port);
    } else {
      var node = _root.findNode(qid);
      node?.resetCleanupTimer();
    }
    var target = data[TARGET_KEY];
    if (target == null || target.length != 20) {
      _krpc.error(tid, address, port, 203, 'invalid arguments');
      return;
    }
    var nodes = _findClosestNode(target);
    _krpc.responseFindNode(tid, nodes, address, port);
  }

  /// `response: {"id" : "<queried nodes id>", "nodes" : "<compact node info>"}`
  /// 没个node是26个字节，前20个是ID，后面6个是IP和端口
  void _processFindNodeResponse(
      List<int> idBytes, InternetAddress address, int port, dynamic data) {
    var qid = ID.createID(idBytes, 0, 20);
    if (qid == _root.id) return;
    var node = _root.findNode(qid);
    node?.resetCleanupTimer();
    if (node != null && node.queried) {
      // 如果节点已经在本地网络中并且findnode过，就不再会对获得的nodes进行处理
      return;
    }
    node ??= Node(qid, PeerValue(address, port), _cleanNodeTime);
    node.queried = true;
    if (_root.add(node)) {
      if (_announceTable.keys.isNotEmpty) {
        // 新加入节点去请求peers
        _announceTable.keys.forEach((infoHash) {
          _requestGetPeers(node, infoHash);
        });
      }
    }
    var nodes = data[NODES_KEY] as List<int>;
    if (nodes == null) return;
    for (var i = 0; i < nodes.length; i += 26) {
      try {
        var id = ID.createID(nodes, i, 20);
        if (_canAdd(id)) {
          var p = PeerValue.parse(nodes, i + 20);
          if (p != null) {
            _tryToGetNode(p.address, p.port);
          }
        }
      } catch (e) {
        log('Process find_node response error:',
            error: e, name: runtimeType.toString());
      }
    }
  }

  List<Node> _findClosestNode(List<int> idBytes) {
    var id = ID.createID(idBytes, 0, 20);
    var node = _root.findNode(id);
    var nodes;
    if (node == null) {
      nodes = _root.findClosestNodes(id);
    } else {
      nodes = <Node>[node];
    }
    return nodes;
  }

  void _requestGetPeers(Node node, String infoHash) {
    if (node.announced[infoHash] != null && node.announced[infoHash]) {
      return;
    }
    Timer.run(() => _krpc.getPeers(infoHash, node.address, node.port));
  }

  void _tryToGetNode(InternetAddress address, int port, [String id]) {
    if (id == null) {
      if (_root != null) {
        id = _root.id.toString();
      }
    }
    if (id != null) {
      Timer.run(() => _krpc.findNode(id, address, port));
    }
  }

  void announce(String infohash, int port) {
    assert(
        infohash != null && infohash.length == 20, 'Incorrect infohash string');
    assert(port != null && port <= 65535 && port >= 0, 'Incorrect port');
    _announceTable[infohash] = port;
    _root?.forEach((node) {
      if (node.announced[infohash] != null && node.announced[infohash]) return;
      var token = node.token[infohash];
      if (token == null) {
        // 还未获取token：
        _requestGetPeers(node, infohash);
      } else {
        node.announced[infohash] = true;
        _krpc.announcePeer(infohash, port, token, node.address, node.port);
      }
    });
  }

  void requestPeers(String infohash) {
    _root.forEach((node) {
      _requestGetPeers(node, infohash);
    });
  }

  void addBootstrapNode(Uri url) async {
    var host = url.host;
    var port = url.port;
    var ip = InternetAddress.tryParse(host);
    if (ip != null) {
      _tryToGetNode(ip, port);
    } else {
      try {
        var ips = await InternetAddress.lookup(host);
        ips.forEach((ip) {
          _tryToGetNode(ip, port);
        });
      } catch (e) {
        log('lookup host error:', error: e, name: runtimeType.toString());
      }
    }
  }
}
