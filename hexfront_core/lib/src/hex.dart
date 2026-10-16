// Hex grid math. Axial (q,r) is the primary key; Cube (x+y+z=0) is used for
// distance/adjacency. All ops are integer-based — no floating point distance
// comparison — to satisfy the determinism constraint (dev-design-doc 3.8).

class Axial {
  final int q;
  final int r;
  const Axial(this.q, this.r);

  Cube get cube => Cube(q, -q - r, r);

  // stable integer key for Map/Set usage (q,r assumed within +/- ~50000)
  int get key => q * 100003 + r;

  Axial neighbor(int dir) => Axial(q + _dirs[dir].q, r + _dirs[dir].r);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Axial && other.q == q && other.r == r;

  @override
  int get hashCode => q.hashCode ^ (r.hashCode << 1);

  @override
  String toString() => '($q,$r)';

  static Axial fromKey(int key) => Axial(key ~/ 100003, key % 100003);
}

class Cube {
  final int x, y, z;
  const Cube(this.x, this.y, this.z);
}

const List<Axial> _dirs = [
  Axial(1, 0),
  Axial(1, -1),
  Axial(0, -1),
  Axial(-1, 0),
  Axial(-1, 1),
  Axial(0, 1),
];

List<Axial> hexNeighbors(Axial a) => [for (var i = 0; i < 6; i++) a.neighbor(i)];

int hexDistance(Axial a, Axial b) {
  final ca = a.cube, cb = b.cube;
  return ((ca.x - cb.x).abs() + (ca.y - cb.y).abs() + (ca.z - cb.z).abs()) ~/ 2;
}

// --- integer min-heap (public so supply.dart can reuse it) ---
class HeapNode {
  final int f;
  final int seq;
  final Axial a;
  final int g;
  HeapNode(this.f, this.seq, this.a, this.g);
}

class MinHeap {
  final List<HeapNode> _d = [];
  bool get isEmpty => _d.isEmpty;

  void push(HeapNode n) {
    _d.add(n);
    var i = _d.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_less(_d[i], _d[p])) {
        final t = _d[i];
        _d[i] = _d[p];
        _d[p] = t;
        i = p;
      } else {
        break;
      }
    }
  }

  HeapNode? pop() {
    if (_d.isEmpty) return null;
    final top = _d[0];
    final last = _d.removeLast();
    if (_d.isNotEmpty) {
      _d[0] = last;
      _sink(0);
    }
    return top;
  }

  void _sink(int i) {
    final n = _d.length;
    while (true) {
      var l = 2 * i + 1, r = 2 * i + 2, s = i;
      if (l < n && _less(_d[l], _d[s])) s = l;
      if (r < n && _less(_d[r], _d[s])) s = r;
      if (s == i) break;
      final t = _d[i];
      _d[i] = _d[s];
      _d[s] = t;
      i = s;
    }
  }

  bool _less(HeapNode a, HeapNode b) =>
      a.f < b.f || (a.f == b.f && a.seq < b.seq);
}

// A* on the hex grid. `walkable` already excludes impassable terrain and blocked
// hexes (e.g. occupied by other units). `stepCost` is the entering cost of a hex
// (>=1). Returns the path including start..goal, or null if unreachable.
List<Axial>? hexAStar(Axial start, Axial goal, Set<Axial> walkable,
    int Function(Axial) stepCost) {
  if (!walkable.contains(start) || !walkable.contains(goal)) return null;
  final cameFrom = <Axial, Axial>{};
  final gScore = <Axial, int>{start: 0};
  final open = MinHeap();
  var seq = 0;
  open.push(HeapNode(hexDistance(start, goal), seq++, start, 0));
  final closed = <Axial>{};
  while (!open.isEmpty) {
    final cur = open.pop()!;
    if (cur.a == goal) {
      final path = <Axial>[cur.a];
      var c = cur.a;
      while (cameFrom.containsKey(c)) {
        c = cameFrom[c]!;
        path.insert(0, c);
      }
      return path;
    }
    if (closed.contains(cur.a)) continue;
    closed.add(cur.a);
    for (final n in hexNeighbors(cur.a)) {
      if (!walkable.contains(n) || closed.contains(n)) continue;
      final tentative = cur.g + stepCost(n);
      final prev = gScore[n];
      if (prev == null || tentative < prev) {
        gScore[n] = tentative;
        cameFrom[n] = cur.a;
        open.push(HeapNode(
            tentative + hexDistance(n, goal), seq++, n, tentative));
      }
    }
  }
  return null;
}
