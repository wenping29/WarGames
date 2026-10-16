import 'package:hexfront_core/hexfront_core.dart';

int _pass = 0, _fail = 0;
void check(String name, bool cond) {
  if (cond) {
    _pass++;
    print('  PASS  $name');
  } else {
    _fail++;
    print('  FAIL  $name');
  }
}

Stats fullStats({int mobility = 4}) => Stats(
      mobility: mobility,
      firepower: 60,
      protection: 40,
      recon: 30,
      supplyCap: 50,
      command: 20,
      coordination: 30,
    );

GameState buildScenario(BalanceData b) {
  final map = HexMap.rectangular(9, 9, Terrain.plain);
  map.cells[Axial(3, 3)] = Terrain.forest;
  final depots = {
    Side.blue: [Axial(0, 0)],
    Side.red: [Axial(8, 8)],
  };
  final units = [
    Unit(id: 'B1', side: Side.blue, type: UnitType.infantry, pos: Axial(1, 1), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100),
    Unit(id: 'B2', side: Side.blue, type: UnitType.armor, pos: Axial(1, 2), stats: fullStats(mobility: 5), strength: 100, maxStrength: 100),
    Unit(id: 'R1', side: Side.red, type: UnitType.infantry, pos: Axial(7, 7), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100),
    Unit(id: 'R2', side: Side.red, type: UnitType.armor, pos: Axial(7, 6), stats: fullStats(mobility: 5), strength: 100, maxStrength: 100),
  ];
  final commanders = [
    Commander(id: 'CB', side: Side.blue, level: 2, pos: Axial(1, 1)),
    Commander(id: 'CR', side: Side.red, level: 1, pos: Axial(7, 7)),
  ];
  return GameState(
    map: map, units: units, commanders: commanders, depots: depots,
    supplyRates: {}, turn: 0, log: [], ruleset: Ruleset.forMode(Mode.pro), balance: b,
  );
}

// Adjacent engagement with the defender supplied from a far depot (low supply in pro mode).
GameState buildAdjacentScenario(BalanceData b) {
  final map = HexMap.rectangular(12, 12, Terrain.plain);
  final depots = {
    Side.blue: [Axial(0, 0)],
    Side.red: [Axial(11, 11)],
  };
  final units = [
    Unit(id: 'ATK', side: Side.blue, type: UnitType.armor, pos: Axial(2, 2), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100),
    Unit(id: 'DEF', side: Side.red, type: UnitType.infantry, pos: Axial(3, 2), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100),
  ];
  return GameState(
    map: map, units: units, commanders: [], depots: depots,
    supplyRates: {}, turn: 0, log: [], ruleset: Ruleset.forMode(Mode.pro), balance: b,
  );
}

void main() {
  final b = BalanceData.load();

  // 1. RNG determinism
  final r1 = SeededRNG(12345), r2 = SeededRNG(12345);
  var rngSame = true;
  for (var i = 0; i < 200; i++) {
    if (r1.nextUint32() != r2.nextUint32()) rngSame = false;
  }
  check('RNG 同种子 → 同序列', rngSame);
  check('RNG 不同种子 → 不同序列',
      SeededRNG(1).nextUint32() != SeededRNG(2).nextUint32());

  // 2. hex distance
  check('hexDistance 相邻=1', hexDistance(Axial(0, 0), Axial(1, 0)) == 1);
  check('hexDistance (3,0)-(0,0)=3', hexDistance(Axial(3, 0), Axial(0, 0)) == 3);
  check('hexDistance 对称',
      hexDistance(Axial(2, 3), Axial(5, 1)) == hexDistance(Axial(5, 1), Axial(2, 3)));

  // 3. A*
  final m = HexMap.rectangular(7, 7, Terrain.plain);
  final walk = m.walkable(blocked: {});
  final path = hexAStar(Axial(0, 0), Axial(6, 0), walk,
      (a) => b.terrainMobility[m.terrainAt(a)]!);
  check('A* 找到直线路径',
      path != null && path.first == Axial(0, 0) && path.last == Axial(6, 0));
  final pathB = hexAStar(Axial(0, 0), Axial(6, 0), m.walkable(blocked: {Axial(3, 0)}),
      (a) => b.terrainMobility[m.terrainAt(a)]!);
  check('A* 绕开阻塞格', pathB != null && !pathB.contains(Axial(3, 0)));

  // 4. supply decay
  final sm = HexMap.rectangular(12, 1, Terrain.plain);
  final srates = supplyRates(sm, [Axial(0, 0)], <Axial>{}, b);
  check('补给 R0 在源点', (srates[Axial(0, 0)] ?? -1) == b.supplyR0);
  check('补给随距离衰减',
      (srates[Axial(1, 0)] ?? 0) < b.supplyR0 &&
          (srates[Axial(2, 0)] ?? 0) < (srates[Axial(1, 0)] ?? 0));
  check('补给单调递减', (srates[Axial(6, 0)] ?? 0) <= (srates[Axial(1, 0)] ?? 0));
  check('补给被切断 → 不可达=0',
      (supplyRates(sm, [Axial(0, 0)], {Axial(1, 0)}, b)[Axial(5, 0)] ?? 0) == 0);

  // 5. CF supply / strength influence
  final uFull = Unit(id: 'x', side: Side.blue, type: UnitType.infantry, pos: Axial(0, 0), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000);
  final uLow = uFull.clone()..supplyRate = 2000;
  final uWeak = uFull.clone()..strength = 50;
  check('补给越低 CF 越低',
      baseCF(uLow, Terrain.plain, b, b.scale) < baseCF(uFull, Terrain.plain, b, b.scale));
  check('建制越低 CF 越低',
      baseCF(uWeak, Terrain.plain, b, b.scale) < baseCF(uFull, Terrain.plain, b, b.scale));

  // 6. combat resolution
  final atk = Unit(id: 'A', side: Side.blue, type: UnitType.armor, pos: Axial(2, 2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  // attacker clearly stronger: armor (base 140, ×1.5 vs artillery) vs artillery (base 80)
  final defArt = Unit(id: 'DA', side: Side.red, type: UnitType.artillery, pos: Axial(3, 2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final res = resolveCombat(atk, defArt, Terrain.plain, Terrain.plain, 1, b);
  check('交战产生伤亡', res.lossDef > 0 && res.lossAtk >= 0);
  check('强者造成更多伤亡 (lossDef>lossAtk)', res.lossDef > res.lossAtk);
  // cover reduces defender loss (armor vs infantry, urban cover)
  final defInf = Unit(id: 'DI', side: Side.red, type: UnitType.infantry, pos: Axial(3, 2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final resPlain = resolveCombat(atk, defInf, Terrain.plain, Terrain.plain, 1, b);
  final resCover = resolveCombat(atk, defInf, Terrain.plain, Terrain.urban, 1, b);
  check('掩体降低守方伤亡', resCover.lossDef < resPlain.lossDef);

  // 7. determinism: same seed -> identical snapshot
  final cmds = <Command>[
    MoveCommand('B1', [Axial(2, 2), Axial(3, 2), Axial(4, 2)]),
    CombatCommand('B2', 'R2'),
  ];
  final a = step(buildScenario(b), cmds, Ruleset.forMode(Mode.pro), b, SeededRNG(777));
  final c = step(buildScenario(b), cmds, Ruleset.forMode(Mode.pro), b, SeededRNG(777));
  check('step 同种子 → 快照一致 (对拍)', a.toSnapshot() == c.toSnapshot());

  // 8. independent builds + same seed identical
  final e = step(buildScenario(b), cmds, Ruleset.forMode(Mode.pro), b, SeededRNG(777));
  final f = step(buildScenario(b), cmds, Ruleset.forMode(Mode.pro), b, SeededRNG(777));
  check('独立构建 + 同种子 → 快照一致', e.toSnapshot() == f.toSnapshot());

  // 9. mode switch actually changes behaviour
  final adj = buildAdjacentScenario(b);
  final pro = step(adj, [CombatCommand('ATK', 'DEF')], Ruleset.forMode(Mode.pro), b, SeededRNG(5));
  final cas = step(adj, [CombatCommand('ATK', 'DEF')], Ruleset.forMode(Mode.casual), b, SeededRNG(5));
  check('模式开关生效 (pro≠casual 快照)', pro.toSnapshot() != cas.toSnapshot());

  print('\n=== 结果: $_pass 通过, $_fail 失败 ===');
  if (_fail > 0) throw Exception('单元测试未通过 ($_fail)');
  print('全部通过 ✓');
}
