import 'dart:convert';
import 'dart:io';
import 'unit.dart';

// External, hot-updatable balance tables (dev-design-doc 3.3 / 3.4).
// Coefficients are fixed-point integers in [0, scale]; scale = 10000 => 1.0.
class BalanceData {
  final int scale;
  final Map<UnitType, int> basePower;
  final Map<Terrain, int> terrainK; // K_terrain attack modifier
  final Map<Terrain, int> terrainCover; // defender cover fraction
  final Map<Terrain, int> terrainMobility; // movement cost per hex
  final Map<String, int> counterMatrix; // "<atk>><def>" -> fixed multiplier
  final int routThreshold;
  final int routStrengthLoss;
  final int routRecoveryMorale;
  final int combatFatigue;
  final int fatigueRecover;
  final int commanderPerLevel;
  final int commandRadius;
  final int rangePenaltyFixed;
  final int artilleryRange;
  final int defaultRange;
  // supply
  final int supplyR0;
  final int retentionFixed; // round(e^-k * scale)
  final int lowSupplyThreshold;
  final int lowSupplyMoraleDrop;
  final int supplyMoraleRecover;
  final int moralePerCasualty;

  BalanceData({
    required this.scale,
    required this.basePower,
    required this.terrainK,
    required this.terrainCover,
    required this.terrainMobility,
    required this.counterMatrix,
    required this.routThreshold,
    required this.routStrengthLoss,
    required this.routRecoveryMorale,
    required this.combatFatigue,
    required this.fatigueRecover,
    required this.commanderPerLevel,
    required this.commandRadius,
    required this.rangePenaltyFixed,
    required this.artilleryRange,
    required this.defaultRange,
    required this.supplyR0,
    required this.retentionFixed,
    required this.lowSupplyThreshold,
    required this.lowSupplyMoraleDrop,
    required this.supplyMoraleRecover,
    required this.moralePerCasualty,
  });

  int moraleK(int morale) {
    final m = morale < 0 ? 0 : (morale > 100 ? 100 : morale);
    return m * scale ~/ 100;
  }

  int counterK(UnitType atk, UnitType def) =>
      counterMatrix['${atk.name}>${def.name}'] ?? scale;

  int maxEngageRange(UnitType t) =>
      t == UnitType.artillery ? artilleryRange : defaultRange;

  static BalanceData defaults() => BalanceData(
        scale: 10000,
        basePower: {
          UnitType.infantry: 100,
          UnitType.armor: 140,
          UnitType.artillery: 80,
          UnitType.motorized: 110,
        },
        terrainK: {
          Terrain.plain: 10000,
          Terrain.forest: 9000,
          Terrain.hill: 11000,
          Terrain.mountain: 8000,
          Terrain.urban: 10500,
          Terrain.water: 6000,
          Terrain.impassable: 0,
        },
        terrainCover: {
          Terrain.plain: 0,
          Terrain.forest: 3000,
          Terrain.hill: 2500,
          Terrain.mountain: 2000,
          Terrain.urban: 4000,
          Terrain.water: 1000,
          Terrain.impassable: 0,
        },
        terrainMobility: {
          Terrain.plain: 1,
          Terrain.forest: 2,
          Terrain.hill: 2,
          Terrain.mountain: 3,
          Terrain.urban: 2,
          Terrain.water: 4,
          Terrain.impassable: 9999,
        },
        counterMatrix: {
          'infantry>armor': 13000,
          'armor>infantry': 8000,
          'armor>artillery': 15000,
          'artillery>infantry': 9000,
          'motorized>infantry': 11000,
          'infantry>motorized': 9000,
        },
        routThreshold: 20,
        routStrengthLoss: 10,
        routRecoveryMorale: 50,
        combatFatigue: 15,
        fatigueRecover: 10,
        commanderPerLevel: 500,
        commandRadius: 3,
        rangePenaltyFixed: 2000,
        artilleryRange: 3,
        defaultRange: 1,
        supplyR0: 10000,
        retentionFixed: 8353,
        lowSupplyThreshold: 4000,
        lowSupplyMoraleDrop: 8,
        supplyMoraleRecover: 3,
        moralePerCasualty: 100,
      );

  static BalanceData fromJson(Map<String, dynamic> c, Map<String, dynamic> s) {
    Terrain terr(String k) =>
        Terrain.values.firstWhere((e) => e.name == k);
    UnitType typ(String k) =>
        UnitType.values.firstWhere((e) => e.name == k);
    Map<UnitType, int> bp = {};
    (c['basePower'] as Map).forEach((k, v) => bp[typ(k as String)] = v as int);
    Map<Terrain, int> tk = {};
    (c['terrainK'] as Map).forEach((k, v) => tk[terr(k as String)] = v as int);
    Map<Terrain, int> tc = {};
    (c['terrainCover'] as Map)
        .forEach((k, v) => tc[terr(k as String)] = v as int);
    Map<Terrain, int> tm = {};
    (c['terrainMobility'] as Map)
        .forEach((k, v) => tm[terr(k as String)] = v as int);
    Map<String, int> cm = {};
    (c['counterMatrix'] as Map)
        .forEach((k, v) => cm[k as String] = v as int);
    return BalanceData(
      scale: c['scale'] as int,
      basePower: bp,
      terrainK: tk,
      terrainCover: tc,
      terrainMobility: tm,
      counterMatrix: cm,
      routThreshold: c['routThreshold'] as int,
      routStrengthLoss: c['routStrengthLoss'] as int,
      routRecoveryMorale: c['routRecoveryMorale'] as int,
      combatFatigue: c['combatFatigue'] as int,
      fatigueRecover: c['fatigueRecover'] as int,
      commanderPerLevel: c['commanderPerLevel'] as int,
      commandRadius: c['commandRadius'] as int,
      rangePenaltyFixed: c['rangePenaltyFixed'] as int,
      artilleryRange: c['artilleryRange'] as int,
      defaultRange: c['defaultRange'] as int,
      supplyR0: s['R0'] as int,
      retentionFixed: s['retentionFixed'] as int,
        lowSupplyThreshold: s['lowSupplyThreshold'] as int,
        lowSupplyMoraleDrop: s['lowSupplyMoraleDrop'] as int,
        supplyMoraleRecover: s['supplyMoraleRecover'] as int,
        moralePerCasualty: c['moralePerCasualty'] as int,
      );
  }

  // Load external JSON tables; fall back to defaults if files are unavailable.
  static BalanceData load([String dir = 'lib/src/data']) {
    try {
      final c = jsonDecode(File('$dir/cf_coef.json').readAsStringSync())
          as Map<String, dynamic>;
      final s = jsonDecode(File('$dir/supply.json').readAsStringSync())
          as Map<String, dynamic>;
      return fromJson(c, s);
    } catch (_) {
      return defaults();
    }
  }
}
