import 'hex.dart';
import 'unit.dart';

// The battle map: a rectangular axial hex grid with per-hex terrain.
// Kept in its own library to avoid a circular import with supply.dart /
// game.dart (which both need HexMap and each other).
class HexMap {
  final int width, height;
  final Map<Axial, Terrain> cells;
  HexMap(this.width, this.height, this.cells);

  static HexMap rectangular(int w, int h, Terrain fill) {
    final cells = <Axial, Terrain>{};
    for (var r = 0; r < h; r++) {
      for (var q = 0; q < w; q++) cells[Axial(q, r)] = fill;
    }
    return HexMap(w, h, cells);
  }

  bool inBounds(Axial a) => cells.containsKey(a);
  Terrain terrainAt(Axial a) => cells[a] ?? Terrain.impassable;

  Set<Axial> walkable({required Set<Axial> blocked}) {
    final s = <Axial>{};
    for (final e in cells.entries) {
      if (e.value != Terrain.impassable && !blocked.contains(e.key)) s.add(e.key);
    }
    return s;
  }
}
