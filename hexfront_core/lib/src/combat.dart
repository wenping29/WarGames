import 'unit.dart';
import 'balance.dart';
import 'rng.dart';

// Combat resolver (dev-design-doc 3.3).
//   CF = BasePower × K_terrain × K_strength × K_supply × K_morale × K_commander × K_counter
//   ratio = CF_attacker / CF_defender
//   lossDef = AttBase × f(ratio, distance, cover)
//   lossAtk = DefBase × g(ratio, distance, cover)
// All arithmetic is fixed-point integer; combat is deterministic unless `dice`
// (a seeded optional variance) is enabled for the semi-pro mode.

class CombatResult {
  final int lossAtk;
  final int lossDef;
  CombatResult(this.lossAtk, this.lossDef);
}

int baseCF(Unit u, Terrain terr, BalanceData b, int commanderK) {
  final scale = b.scale;
  int cf = b.basePower[u.type]!;
  cf = cf * (b.terrainK[terr] ?? scale) ~/ scale;
  final strFrac =
      u.maxStrength > 0 ? (u.strength * scale ~/ u.maxStrength) : 0;
  cf = cf * strFrac ~/ scale;
  cf = cf * (u.supplyRate > 0 ? u.supplyRate : 0) ~/ scale; // K_supply
  cf = cf * b.moraleK(u.morale) ~/ scale;
  cf = cf * commanderK ~/ scale;
  return cf;
}

CombatResult resolveCombat(
  Unit atk,
  Unit def,
  Terrain atkTerr,
  Terrain defTerr,
  int distance,
  BalanceData b, {
  int atkCmdK = 10000,
  int defCmdK = 10000,
  bool dice = false,
  SeededRNG? rng,
}) {
  final scale = b.scale;
  int a = baseCF(atk, atkTerr, b, atkCmdK);
  int d = baseCF(def, defTerr, b, defCmdK);
  a = a * b.counterK(atk.type, def.type) ~/ scale;
  d = d * b.counterK(def.type, atk.type) ~/ scale;
  // ranged units keep effectiveness at distance; others degrade
  if (distance > 1 && atk.type != UnitType.artillery) {
    a = a * scale ~/ (scale + (distance - 1) * b.rangePenaltyFixed);
  }
  int total = a + d;
  if (total <= 0) total = 1;
  final defShare = a * scale ~/ total;
  final atkShare = d * scale ~/ total;

  int lossDef = atk.strength * defShare ~/ scale;
  final cover = b.terrainCover[defTerr] ?? 0;
  lossDef = lossDef * (scale - cover) ~/ scale; // cover reduces defender loss

  int lossAtk = def.strength * atkShare ~/ scale;

  if (dice && rng != null) {
    // +/- 5% deterministic variance, seeded
    final vA = rng.nextFixed(scale ~/ 10);
    final vD = rng.nextFixed(scale ~/ 10);
    lossAtk = lossAtk * (scale + vA - (scale ~/ 20)) ~/ scale;
    lossDef = lossDef * (scale + vD - (scale ~/ 20)) ~/ scale;
  }
  return CombatResult(lossAtk, lossDef);
}
