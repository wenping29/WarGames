import 'package:hexfront_core/hexfront_core.dart';

Stats fullStats({int mobility = 4}) => Stats(
      mobility: mobility,
      firepower: 60,
      protection: 40,
      recon: 30,
      supplyCap: 50,
      command: 20,
      coordination: 30,
    );

void main() {
  final b = BalanceData.load();
  print('=== HEXFRONT 内核垂直切片 · 演示 ===');
  print('平衡表来源: ${b.runtimeType} (scale=${b.scale}, supplyR0=${b.supplyR0}, retention=${b.retentionFixed})\n');

  // ---- 地图 / 初始部署 (9x9) ----
  final map = HexMap.rectangular(9, 9, Terrain.plain);
  map.cells[Axial(3, 3)] = Terrain.forest;
  map.cells[Axial(4, 3)] = Terrain.hill;
  map.cells[Axial(5, 4)] = Terrain.urban;
  final depots = {
    Side.blue: [Axial(0, 0)],
    Side.red: [Axial(8, 8)],
  };
  final units = [
    Unit(id: 'B1', side: Side.blue, type: UnitType.infantry, pos: Axial(1, 1), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100),
    Unit(id: 'B2', side: Side.blue, type: UnitType.armor, pos: Axial(1, 2), stats: fullStats(mobility: 5), strength: 100, maxStrength: 100),
    Unit(id: 'R1', side: Side.red, type: UnitType.infantry, pos: Axial(6, 7), stats: fullStats(mobility: 4), strength: 100, maxStrength: 100),
    Unit(id: 'R2', side: Side.red, type: UnitType.armor, pos: Axial(7, 6), stats: fullStats(mobility: 5), strength: 100, maxStrength: 100),
  ];
  final commanders = [
    Commander(id: 'CB', side: Side.blue, level: 2, pos: Axial(1, 1)),
  ];
  final rs = Ruleset.forMode(Mode.pro);
  var state = GameState(
    map: map, units: units, commanders: commanders, depots: depots,
    supplyRates: {}, turn: 0, log: [], ruleset: rs, balance: b,
  );

  // 回合1：补给结算（基于初始位置）
  state = step(state, [], rs, b, SeededRNG(1));
  print('[1] 开局补给率（单位越远离补给源，补给率越低）');
  for (final u in state.units) {
    print('   ${u.id.padRight(3)} @ ${u.pos}  补给=${(u.supplyRate / 100).toStringAsFixed(1)}%  士气=${u.morale}');
  }

  // 回合2：蓝方机动推进
  final cmds2 = <Command>[
    MoveCommand('B1', [Axial(2, 1), Axial(3, 1), Axial(4, 1), Axial(4, 2)]),
    MoveCommand('B2', [Axial(2, 3), Axial(3, 4), Axial(4, 5), Axial(5, 6)]),
  ];
  state = step(state, cmds2, rs, b, SeededRNG(2));
  print('\n[2] 第2回合机动后位置（补给仍按回合初位置结算，存在 1 回合滞后）');
  for (final u in state.units) {
    print('   ${u.id.padRight(3)} @ ${u.pos}  补给=${(u.supplyRate / 100).toStringAsFixed(1)}%');
  }

  // 回合3：空指令，按新位置重算补给 → 体现推进后补给下降
  state = step(state, [], rs, b, SeededRNG(3));
  print('\n[3] 第3回合重算补给（推进后显著降低）');
  for (final u in state.units) {
    print('   ${u.id.padRight(3)} @ ${u.pos}  补给=${(u.supplyRate / 100).toStringAsFixed(1)}%');
  }

  // 补给线切断演示（护城河机制）：单线走廊，敌方占据唯一通道即切断
  print('\n[4] 补给线切断演示（护城河）: 单线走廊，红方占据 (2,0)');
  final corr = HexMap.rectangular(8, 1, Terrain.plain);
  final open = supplyRates(corr, [Axial(0, 0)], <Axial>{}, b)[Axial(5, 0)] ?? 0;
  final cut = supplyRates(corr, [Axial(0, 0)], {Axial(2, 0)}, b)[Axial(5, 0)] ?? 0;
  print('   走廊末端单位 通畅=${(open / 100).toStringAsFixed(1)}%  →  通道被占=${(cut / 100).toStringAsFixed(1)}%');

  // 邻接交战解析演示
  print('\n[5] 邻接交战解析（装甲 vs 步兵, 满补给满士气, 无掩体）');
  final cmap = HexMap.rectangular(5, 5, Terrain.plain);
  final catk = Unit(id: 'ATK', side: Side.blue, type: UnitType.armor, pos: Axial(2,2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final cdef = Unit(id: 'DEF', side: Side.red, type: UnitType.infantry, pos: Axial(3,2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final cfA = baseCF(catk, Terrain.plain, b, b.scale);
  final cfD = baseCF(cdef, Terrain.plain, b, b.scale);
  print('   CF(ATK)=$cfA  CF(DEF)=$cfD  战力比=${(cfA / cfD).toStringAsFixed(2)}');
  final after = step(
    GameState(map: cmap, units: [catk, cdef], commanders: [], depots: {Side.blue: [Axial(0,0)], Side.red: [Axial(4,4)]}, supplyRates: {}, turn: 0, log: [], ruleset: rs, balance: b),
    [CombatCommand('ATK', 'DEF')], rs, b, SeededRNG(9),
  );
  final a2 = after.findUnit('ATK')!, d2 = after.findUnit('DEF')!;
  print('   交战后: ATK 建制=${a2.strength}/${a2.maxStrength} 士气=${a2.morale}  ||  DEF 建制=${d2.strength}/${d2.maxStrength} 士气=${d2.morale}');

  print('\n[6] 快照可回放性: 长度=${state.toSnapshot().length}（同种子双端重算应逐字节一致）');
  print('演示完成 ✓');
}
