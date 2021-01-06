import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:dht_dart/src/kademlia/id.dart';
import 'package:dht_dart/src/kademlia/node.dart';
import 'package:dht_dart/src/krpc/krpc_message.dart';
import 'package:dht_dart/src/kademlia/bucket.dart';
import 'package:dht_dart/src/kademlia/tree_node.dart';
import 'package:test/test.dart';

void main() {
  group('some inner test', () {
    test('random id', () {
      void _createPartSameId(int index) {
        var l = index + 1;
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
        var r = Random();
        for (var i = j + 1; i < 20; i++) {
          newId[i] = r.nextInt(256);
        }
        var nid = ID.createID(newId);

        assert(nid.differentLength(id) == l);
      }

      for (var i = -1; i < 160; i++) {
        _createPartSameId(i);
      }
    });
  });

  group('PeerValue - ', () {
    test('Create/Parse', () {
      var peerValue =
          CompactAddress(InternetAddress.tryParse('128.2.1.3'), 12311);
      var bytes = peerValue.toBytes();
      var p2 = CompactAddress.parseIPv4Address(bytes);
      assert(
          p2.port == peerValue.port &&
              p2.addressString == peerValue.addressString,
          'Parse error');
    });

    test('Contact encoding string', () {
      var peerValue =
          CompactAddress(InternetAddress.tryParse('128.2.1.3'), 12311);
      var str = peerValue.toContactEncodingString();
      var bs = latin1.encode(str);
      assert(bs.length == 6);
      var p2 = CompactAddress.parseIPv4Address(bs);
      assert(
          (p2.port == peerValue.port) &&
              (p2.addressString == peerValue.addressString) &&
              (str == p2.toContactEncodingString()),
          'Parse error');
    });

    test('Parse More than one', () {
      var r = Random();
      var n = 10;
      var testBytes = <int>[];
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < 6; j++) {
          testBytes.add(r.nextInt(256));
        }
      }
      var offset = 0;
      for (var i = 0; i < n; i++, offset += 6) {
        var p2 = CompactAddress.parseIPv4Address(testBytes, offset);
        var b = p2.toBytes();
        for (var h = 0; h < 6; h++) {
          assert(b[h] == testBytes[offset + h]);
        }
      }
    });
  });

  group('binary tree test ', () {
    var idByteLength = 20;
    test('bucket', () {
      for (var i = 0; i < 160; i++) {
        print(Bucket(i, 100).bucketMaxSize);
      }
    });

    test('add node', () {
      var root = Bucket(5);
      var node = Node(ID.randomID(idByteLength), null);
      var node2 = Node(ID.randomID(idByteLength), null);

      var nullNode = root.addNode(null);
      assert(nullNode == null);
      assert(root.isEmpty, 'unknown error');
      assert(root.count == 0, 'unknown error');
      var tn = root.addNode(node);
      var tn2 = root.addNode(node2);
      assert(root.addNode(null) == null);
      assert(root.isNotEmpty);
      assert(root.count == 2);
      var func;
      func = (TreeNode node, List<bool> re) {
        if (node.parent != null) {
          if (node.parent.left == node) {
            re.insert(0, true);
          }
          if (node.parent.right == node) {
            re.insert(0, false);
          }
        } else {
          return re;
        }
        return func(node.parent, re);
      };

      var r = func(tn, <bool>[]);
      var r2 = func(tn2, <bool>[]);
      assert(r.length == idByteLength * 8, 'unknown error');
      var func2 = (List<bool> r) {
        var rN = <int>[];
        for (var i = 0; i < idByteLength; i++) {
          var s = '';
          for (var j = 0; j < 8; j++) {
            if (r[i * 8 + j]) {
              s += '1';
            } else {
              s += '0';
            }
          }
          rN.insert(0, int.parse(s, radix: 2));
        }
        return rN;
      };
      var rN = func2(r);
      var rN2 = func2(r2);
      for (var i = 0; i < rN.length; i++) {
        assert(
            (rN[i] == node.id.getValueAt(i)) &&
                (rN2[i] == node2.id.getValueAt(i)),
            'create binary tree error');
      }
    });

    test('find node', () {
      var root = Bucket(5);
      var id1 = ID.randomID(idByteLength);
      var id2 = ID.randomID(idByteLength);
      var id3 = ID.randomID(idByteLength);
      var node = Node(id1, null);
      var node2 = Node(id2, null);
      var node3 = Node(id3, null);
      root.addNode(node);
      root.addNode(node2);
      root.addNode(node3);
      assert(root.findNode(ID.randomID(idByteLength)) == null,
          'its impossible! unless the random bytes is same');
      assert(root.findNode(id1).node == node, 'search error');
      assert(root.findNode(id2).node != node, 'search error');
      assert(root.findNode(id2).node == node2, 'search error');
    });

    test('remove node', () {
      var root = Bucket(5);
      var id1 = ID.randomID(idByteLength);
      var id2 = ID.randomID(idByteLength);
      var id3 = ID.randomID(idByteLength);
      var nullNode = root.removeNode(id1);
      assert(nullNode == null);
      assert(root.isEmpty);
      var node = Node(id1, null);
      var node2 = Node(id2, null);
      var node3 = Node(id3, null);
      var tn1 = root.addNode(node);
      var tn2 = root.addNode(node2);
      var tn3 = root.addNode(node3);

      assert(root.removeNode(node) == tn1);
      assert(root.isNotEmpty && root.count == 2);
      assert(root.removeNode(tn2) == tn2);
      assert(root.isNotEmpty && root.count == 1);
      assert(root.removeNode(node3.id) == tn3);
      assert(root.isEmpty);

      nullNode = root.removeNode(id1);
      assert(nullNode == null);
      assert(root.isEmpty);
    });
  });

  group('Nodes - ', () {
    test(' ID compare', () {
      var id = ID.randomID(20);
      var root = Node(id, null);
      var target = Node(id, null);
      assert(root.id.differentLength(target.id) == 0);

      var id2 = <int>[];
      for (var i = 0; i < root.id.byteLength - 1; i++) {
        id2.add(root.id.getValueAt(i));
      }
      var last = root.id.getValueAt(19);
      var l = Random().nextInt(256);
      while (l == last) {
        l = Random().nextInt(256);
      }
      id2.add(l);

      assert(root.id.differentLength(ID.createID(id2)) <= 8);
    });

    test(' Find closest', () {
      var count = 40;
      var root = Node(ID.randomID(20), null);
      for (var i = 0; i < count; i++) {
        var n = Node(ID.randomID(20), null);
        root.add(n);
      }
      var id = <int>[];
      for (var i = 0; i < root.id.byteLength - 1; i++) {
        id.add(root.id.getValueAt(i));
      }
      var last = root.id.getValueAt(19);
      var l = Random().nextInt(256);
      while (l == last) {
        l = Random().nextInt(256);
      }
      id.add(l);
      var target = Node(ID.createID(id), null);
      var re = root.findClosestNodes(target.id);
      assert(re.length == 8);
    });
  });

  group('KRPC - ', () {
    test('ping message', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var bytes = pingMessage(tid, nid);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'q', 'y error');
      assert(String.fromCharCodes(obj['q']) == 'ping', 'q error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['a']['id']) == nid, 'node id error');
    });

    test('ping response', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var bytes = pongMessage(tid, nid);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'r', 'y error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['r']['id']) == nid, 'node id error');
    });

    test('find_node message', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var bytes = findNodeMessage(tid, nid, nid);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'q', 'y error');
      assert(String.fromCharCodes(obj['q']) == 'find_node', 'q error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['a']['id']) == nid, 'node id error');
      assert(
          String.fromCharCodes(obj['a']['target']) == nid, 'target id error');
    });

    test('find_node message', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var nodes = <Node>[];
      nodes.add(Node(ID.randomID(20),
          CompactAddress(InternetAddress.tryParse('120.0.0.1'), 2222)));
      nodes.add(Node(ID.randomID(20),
          CompactAddress(InternetAddress.tryParse('196.168.0.1'), 2223)));
      var bytes = findNodeResponse(tid, nid, nodes);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'r', 'y error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['r']['id']) == nid, 'node id error');
      var nodeBytes = obj['r']['nodes'];
      assert(nodeBytes.length == 26 * nodes.length);
      var rns = [];
      for (var i = 0; i < nodeBytes.length; i += 26) {
        var id = ID.createID(nodeBytes, i, 20);
        var peerValue = CompactAddress.parseIPv4Address(nodeBytes, i + 20);
        rns.add(Node(id, peerValue));
      }
      assert(rns.length == nodes.length);
      for (var i = 0; i < rns.length; i++) {
        var n1 = nodes[i];
        var n2 = rns[i];
        assert(n1.id == n2.id);
        assert(n1.address == n2.address);
        assert(n1.port == n2.port);
      }
    });

    test('get_peers message', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var infoHash = ID.randomID(20).toString();
      var bytes = getPeersMessage(tid, nid, infoHash);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'q', 'y error');
      assert(String.fromCharCodes(obj['q']) == 'get_peers', 'q error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['a']['id']) == nid, 'node id error');
      assert(
          String.fromCharCodes(obj['a']['info_hash']).length == 20 &&
              String.fromCharCodes(obj['a']['info_hash']) == infoHash,
          'info_hash id error');
    });

    test('get_peers response1', () {
      var testId = ID.randomID(2);
      var tid = testId.toString();
      var nid = ID.randomID(20).toString();
      var peers = <CompactAddress>[];

      var r = Random();
      var n = 10;
      var testBytes = <int>[];
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < 6; j++) {
          testBytes.add(r.nextInt(256));
        }
      }
      var offset = 0;
      for (var i = 0; i < n; i++, offset += 6) {
        peers.add(CompactAddress.parseIPv4Address(testBytes, offset));
      }

      var bytes = getPeersResponse(tid, nid, 'token', peers: peers);
      var obj = decode(bytes);
      assert(String.fromCharCodes(obj['y']) == 'r', 'y error');
      assert(String.fromCharCodes(obj['t']) == tid, 'transaction id error');
      assert(String.fromCharCodes(obj['r']['id']) == nid, 'node id error');
      assert(obj['r']['values'].length == n);

      var pbs = obj['r']['values'];
      for (var i = 0; i < pbs.length; i++) {
        var ps = pbs[i];
        var p = CompactAddress.parseIPv4Address(ps);
        assert(peers[i].addressString == p.addressString);
        assert(peers[i].port == p.port);
      }
    });
  });
}

String idListToRadix2String(List<int> id) {
  var s = '';
  for (var i = id.length - 1; i >= 0; i--) {
    s = '$s${intToRadix2String(id[i])}';
  }
  return s;
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

List<int> randomBytes(count) {
  var random = Random();
  var bytes = List<int>(count);
  for (var i = 0; i < count; i++) {
    bytes[i] = random.nextInt(254);
  }
  return bytes;
}
