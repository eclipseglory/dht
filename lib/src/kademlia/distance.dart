class Distance {
  final List<int> _values;

  String _str;

  int get byteLength => _values.length;

  Distance(this._values);

  int getValue(int index) {
    return _values[index];
  }

  @override
  String toString() {
    _str ??= String.fromCharCodes(_values);
    return _str;
  }

  @override
  int get hashCode => toString().hashCode;

  @override
  bool operator ==(a) {
    if (a is Distance) {
      if (a.byteLength == byteLength) {
        for (var i = 0; i < byteLength; i++) {
          if (getValue(i) != a.getValue(i)) return false;
        }
        return true;
      }
    }
    return false;
  }

  bool operator >=(a) {
    if (a is Distance) {
      if (a.byteLength == byteLength) {
        for (var i = 0; i < byteLength; i++) {
          if (a.getValue(i) > getValue(i)) return false;
        }
        return true;
      } else {
        throw 'Different bytelength can not compare';
      }
    } else {
      throw 'Different type can not compare';
    }
  }

  bool operator >(a) {
    if (a is Distance) {
      return a != this && this >= a;
    } else {
      throw 'Different type can not compare';
    }
  }

  bool operator <=(a) {
    if (a is Distance) {
      return a > this;
    } else {
      throw 'Different type can not compare';
    }
  }

  bool operator <(a) {
    if (a is Distance) {
      return a != this && this <= a;
    } else {
      throw 'Different type can not compare';
    }
  }
}
