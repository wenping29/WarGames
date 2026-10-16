import 'hex.dart';
import 'map.dart';
import 'balance.dart';
import 'unit.dart';

// Logistics / supply-line solver — the product's差异化护城河 (dev-design-doc 3.4).
// Supply rate decays exponentially with hop count from the nearest depot:
//   R(d) = R0 * retention^d   (retention = round(e^-k * scale)), computed in
//   integer fixed-point so it is bit-identical across platforms.

// Multi-source Dijkstra. Each step costs 1 hop; impassable terrain and `blocked`
// hexes (enemy-occupied) are excluded. Returns hop distance from nearest depot.
Map<Axial, int> supplyDistances(
    HexMap map, List<Axial> depots, Set<Axial> blocked) {
  final dist = <Axial, int>{};
  final open = MinHeap();
  var seq = 0;
  for (final d in depots) {
    if (map.inBounds(d) && !blocked.contains(d)) {
      dist[d] = 0;
      open.push(HeapNode(0, seq++, d, 0));
    }
  }
  final closed = <Axial>{};
  while (!open.isEmpty) {
    final cur = open.pop()!;
    if (closed.contains(cur.a)) continue;
    closed.add(cur.a);
    for (final n in hexNeighbors(cur.a)) {
      if (!map.inBounds(n)) continue;
      if (map.terrainAt(n) == Terrain.impassable) continue;
      if (blocked.contains(n)) continue;
      final nd = cur.g + 1;
      final prev = dist[n];
      if (prev == null || nd < prev) {
        dist[n] = nd;
        open.push(HeapNode(nd, seq++, n, nd));
      }
    }
  }
  return dist;
}

Map<Axial, int> supplyRates(HexMap map, List<Axial> depots, Set<Axial> blocked,
    BalanceData b) {
  final dist = supplyDistances(map, depots, blocked);
  final rates = <Axial, int>{};
  for (final e in dist.entries) {
    var rate = b.supplyR0;
    for (var i = 0; i < e.value; i++) {
      rate = rate * b.retentionFixed ~/ b.scale;
    }
    rates[e.key] = rate;
  }
  return rates;
}
