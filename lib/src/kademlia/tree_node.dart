import 'id.dart';
import 'node.dart';

/// left : 1, right :0
class TreeNode {
  Node node;

  TreeNode _left;

  TreeNode _right;

  TreeNode parent;

  TreeNode();

  TreeNode get left => _left;

  TreeNode get right => _right;

  set right(TreeNode n) {
    if (_right == n) return;
    if (_right != null) {
      _right.parent = null;
      // throw 'Can not set child node because it\'s not null , try to remove it and set new one';
    }
    if (n != null && n.parent != null) {
      if (n.parent.left == n) n.parent.left = null;
      if (n.parent.right == n) n.parent.right = null;
    }
    if (n != null) {
      n.parent = this;
    }
    _right = n;
  }

  set left(TreeNode n) {
    if (_left == n) return;
    if (_left != null) {
      _left.parent = null;
      // throw 'Can not set child node because it\'s not null , try to remove it and set new one';
    }
    if (n != null) {
      if (n.parent != null) {
        if (n.parent.left == n) n.parent.left = null;
        if (n.parent.right == n) n.parent.right = null;
      }
      n.parent = this;
    }
    _left = n;
  }

  TreeNode findNode(ID id, [int offset = 0]) {
    if (id == null) throw 'ID can not be null ';
    if (offset >= id.byteLength * 8) return this;
    var index = offset ~/ 8;
    var n = offset.remainder(8);
    var number = id.getValueAt(id.byteLength - index - 1);
    var base = BASE_NUM;
    base = base >> n;
    TreeNode next;
    // TreeNode another;
    if (base & number == 0) {
      next = right;
      // another = left;
    } else {
      next = left;
      // another = right;
    }
    var result = next?.findNode(id, ++offset);
    // result ??= another?.findNode(id, ++offset);
    return result;
  }

  void dispose() {
    var temp1 = _left;
    var temp2 = _right;
    if (temp1 != null) {
      temp1.dispose();
    }
    if (temp2 != null) {
      temp2.dispose();
    }
    parent = null;
    _left = null;
    _right = null;
    if (node != null) {
      node.dispose();
    }
    node = null;
  }
}
