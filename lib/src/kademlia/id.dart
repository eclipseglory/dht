import 'dart:math';

import 'distance.dart';

const BASE_NUM = 128;

class ID {
  List<int> _ids;

  String _str;

  ID([int byteLength = 20]) {
    _ids = List<int>(byteLength);
  }

  int get byteLength => _ids.length;

  void setValue(List<int> values, [int offset = 0]) {
    if (_ids.length > (values.length - offset)) {
      throw 'values length is not match the ID bytelength';
    }
    for (var i = 0; i < _ids.length; i++) {
      _ids[i] = values[i + offset];
    }
    _str = null;
  }

  int getValueAt(int index) {
    if (index < 0 || index > _ids.length - 1) throw 'Index over range';
    return _ids[index];
  }

  void setValueAt(int index, int value) {
    if (index < 0 || index > _ids.length - 1) throw 'Index over range';
    if (_ids[index] != value) {
      _ids[index] = value;
      _str = null;
    }
  }

  Distance distanceBetween(ID id) {
    if (id.byteLength != byteLength) throw 'ID Different Length';
    var ids = List<int>(_ids.length);
    for (var i = 0; i < _ids.length; i++) {
      ids[i] = id.getValueAt(i) ^ _ids[i];
    }
    return Distance(ids);
  }

  int differentLength(ID ids) {
    if (ids.byteLength != byteLength) throw 'ID Different Length';
    var lrp = _ids.length * 8;
    var base = BASE_NUM;
    for (var i = 0; i < _ids.length; i++) {
      var xor = _ids[i] ^ ids.getValueAt(i);
      if (xor != 0) {
        var offset = 0;
        var r = xor & base;
        while (r == 0) {
          offset++;
          base = base >> 1;
          r = xor & base;
        }
        lrp -= offset;
        break;
      } else {
        lrp -= 8;
      }
    }
    return lrp;
  }

  static ID createID(List<int> values, [int offset = 0, int length]) {
    length ??= values.length;
    var id = ID(length);
    id.setValue(values, offset);
    return id;
  }

  static ID randomID([int byteLength = 20]) {
    var id = ID(byteLength);
    var r = Random();
    for (var i = 0; i < byteLength; i++) {
      id.setValueAt(i, r.nextInt(256));
    }
    return id;
  }

  @override
  String toString() {
    _str ??= String.fromCharCodes(_ids);
    return _str;
  }

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(a) {
    if (a is ID) {
      if (a.byteLength == byteLength) {
        var l = differentLength(a);
        return l == 0;
      }
    }
    return false;
  }

  int operator [](int index) {
    return _ids[index];
  }
}
