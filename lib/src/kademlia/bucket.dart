import 'dart:math';

import 'id.dart';
import 'node.dart';
import 'tree_node.dart';

class Bucket extends TreeNode {
  final int _maxSize;

  final List<Node> _nodes = <Node>[];

  final Set<void Function(Bucket bucket)> _emptyHandler =
      <void Function(Bucket bucket)>{};

  int _count = 0;

  final int index;

  Bucket(this.index, [this._maxSize = 8]);

  bool get isEmpty => _count == 0;

  bool get isNotEmpty => !isEmpty;

  bool get isFull => _count >= bucketMaxSize;

  bool get isNotFull => !isFull;

  int get count => _count;

  List<Node> get nodes => _nodes;

  TreeNode? addNode(Node? node) {
    if (node == null) return null;
    if (_count >= bucketMaxSize) {
      return null;
    } else {
      var currentNode = _generateTreeNode(node.id);
      if (currentNode.node == null) {
        _count++;
        currentNode.node = node;
        _nodes.add(node);
        node.onTimeToCleanup(_nodeIsOutTime);
        return currentNode;
      } else {
        currentNode.node = node;
        return currentNode;
      }
    }
  }

  int get bucketMaxSize {
    if (index > 62) {
      return _maxSize;
    }
    return min(_maxSize, pow(2, index).toInt());
  }

  void _nodeIsOutTime(Node node) {
    node.offTimeToCleanup(_nodeIsOutTime);
    removeNode(node);
  }

  TreeNode? removeNode(dynamic a) {
    if (a == null) return null;
    ID? id;
    if (a is TreeNode) {
      var n = a.node;
      if (n == null) return null;
      id = n.id;
    }
    if (a is Node) {
      id = a.id;
    }
    if (a is ID) {
      id = a;
    }
    if (id == null) return null;
    var t = findNode(id);
    if (t != null) {
      var node = t.node;
      _count--;
      _nodes.remove(node);
      t.dispose();
      if (isEmpty) {
        _fireEmptyEvent();
      }
      return t;
    }
    return null;
  }

  void _fireEmptyEvent() {
    _emptyHandler.forEach((element) {
      element(this);
    });
  }

  bool onEmpty(void Function(Bucket b) h) {
    return _emptyHandler.add(h);
  }

  bool offEmpty(void Function(Bucket b) h) {
    return _emptyHandler.remove(h);
  }

  TreeNode _generateTreeNode(ID id) {
    TreeNode currentNode = this;
    for (var i = id.byteLength - 1; i >= 0; i--) {
      var n = id.getValueAt(i);
      var base = BASE_NUM;
      for (var i = 0; i < 8; i++) {
        TreeNode? next;
        if (n & base == 0) {
          next = currentNode.right;
          next ??= TreeNode();
          currentNode.right = next;
        } else {
          next = currentNode.left;
          next ??= TreeNode();
          currentNode.left = next;
        }
        currentNode = next;
        base = base >> 1;
      }
    }
    return currentNode;
  }

  @override
  void dispose() {
    super.dispose();
    _emptyHandler.clear();
    _nodes.forEach((element) {
      element.dispose();
    });
    _nodes.clear();
    _count = 0;
  }

  @override
  String toString() {
    return 'Bucket($_count) : $index';
  }
}
