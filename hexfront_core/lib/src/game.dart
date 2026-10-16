import 'dart:math' as math;
import 'hex.dart';
import 'unit.dart';
import 'map.dart';
import 'supply.dart';
import 'combat.dart';
import 'balance.dart';
import 'rng.dart';

// --- Mode / Ruleset (四杠杆) ------------------------------------------------

enum Mode { pro, semi, casual }

class Ruleset {
  final Mode mode;
  final bool supplyEnabled;
  final bool moraleEnabled;
  final bool attritionEnabled;
  final bool commanderEnabled;
  final bool counterEnabled;
  final bool diceEnabled;
  final bool fatigueEnabled;

  Ruleset({
    required this.mode,
    required this.supplyEnabled,
    required this.moraleEnabled,
    required this.attritionEnabled,
    required this.commanderEnabled,
    required this.counterEnabled,
    required this.diceEnabled,
    required this.fatigueEnabled,
  });

  static Ruleset forMode(Mode m) {
    switch (m) {
      case Mode.pro:
        return Ruleset(
          mode: m,
          supplyEnabled: true,
          moraleEnabled: true,
          attritionEnabled: true,
          commanderEnabled: true,
          counterEnabled: true,
          diceEnabled: false,
          fatigueEnabled: true,
        );
      case Mode.semi:
        return Ruleset(
          mode: m,
          supplyEnabled: true,
          moraleEnabled: true,
          attritionEnabled: true,
          commanderEnabled: true,
          counterEnabled: true,
          diceEnabled: true,
          fatigueEnabled: true,
        );
      case Mode.casual:
        return Ruleset(
          mode: m,
          supplyEnabled: true,
          moraleEnabled: false,
          attritionEnabled: false,
          commanderEnabled: false,
          counterEnabled: false,
          diceEnabled: false,
          fatigueEnabled: false,
        );
    }
  }
}

// --- Commands --------------------------------------------------------------

abstract class Command {
  String get orderKey; // deterministic ordering key
}

class MoveCommand extends Command {
  final String unitId;
  final List<Axial> path;
  MoveCommand(this.unitId, this.path);
  @override
  String get orderKey => unitId;
}

class CombatCommand extends Command {
  final String attackerId;
  final String defenderId;
  CombatCommand(this.attackerId, this.defenderId);
  @override
  String get orderKey => attackerId;
}

// --- Game State ------------------------------------------------------------

class GameState {
  HexMap map;
  List<Unit> units;
  List<Commander> commanders;
  Map<Side, List<Axial>> depots;
  Map<Axial, int> supplyRates;
  int turn;
  List<String> log;
  Ruleset ruleset;
  BalanceData balance;

  GameState({
    required this.map,
    required this.units,
    required this.commanders,
    required this.depots,
    required this.supplyRates,
    required this.turn,
    required this.log,
    required this.ruleset,
    required this.balance,
  });

  Unit? findUnit(String id) {
    for (final u in units) if (u.id == id) return u;
    return null;
  }

  GameState clone() => GameState(
        map: map, // immutable, shared
        units: [for (final u in units) u.clone()],
        commanders: [for (final c in commanders) c.clone()],
        depots: {for (final e in depots.entries) e.key: [...e.value]},
        supplyRates: {...supplyRates},
        turn: turn,
        log: [...log],
        ruleset: ruleset,
        balance: balance,
      );

  // Canonical, order-independent snapshot string for replay/对拍 equality.
  String toSnapshot() {
    final us = [...units]..sort((a, b) => a.id.compareTo(b.id));
    final uStr = us
        .map((u) =>
            '${u.id}:${u.side.name}:${u.type.name}:${u.pos.q},${u.pos.r}:'
            '${u.strength}/${u.maxStrength}:${u.morale}:${u.fatigue}:'
            '${u.supplyRate}:${u.status.name}')
        .join('|');
    final ms = supplyRates.keys.toList()..sort((a, b) => a.key.compareTo(b.key));
    final mStr = ms.map((a) => '${a.q},${a.r}:${supplyRates[a]}').join('|');
    return 'T=$turn#U=$uStr#S=$mStr';
  }
}

// --- Scheduler / step ------------------------------------------------------

// Deterministic turn pipeline (dev-design-doc 3.7):
//   Supply → State update → Command acceptance → Combat resolution → Attrition/Reorg → Turn end
GameState step(GameState s, List<Command> cmds, Ruleset r, BalanceData b,
    SeededRNG rng) {
  final ns = s.clone();
  ns.ruleset = r;
  ns.balance = b;

  // Phase 1: Supply settlement
  if (r.supplyEnabled) _resolveSupply(ns, b);

  // Phase 2: State update (morale coupled to supply)
  _updateStates(ns, b, r);

  // Phase 3: Command acceptance (deterministic order)
  final ordered = [...cmds]..sort((a, c) => a.orderKey.compareTo(c.orderKey));
  final engagements = <String, String>{};
  for (final cmd in ordered) {
    if (cmd is MoveCommand) {
      _applyMove(ns, cmd, b, r);
    } else if (cmd is CombatCommand) {
      final atk = ns.findUnit(cmd.attackerId);
      if (atk != null && atk.status != UnitStatus.eliminated) {
        atk.status = UnitStatus.engaged;
        engagements[cmd.attackerId] = cmd.defenderId;
      }
    }
  }

  // Phase 4: Combat resolution
  final atkIds = engagements.keys.toList()..sort();
  for (final atkId in atkIds) {
    final defId = engagements[atkId]!;
    final atk = ns.findUnit(atkId);
    final def = ns.findUnit(defId);
    if (atk == null || def == null) continue;
    if (atk.status == UnitStatus.eliminated ||
        def.status == UnitStatus.eliminated) continue;
    final dist = hexDistance(atk.pos, def.pos);
    if (dist > b.maxEngageRange(atk.type)) continue;
    final atkTerr = ns.map.terrainAt(atk.pos);
    final defTerr = ns.map.terrainAt(def.pos);
    final atkCmd =
        r.commanderEnabled ? _commanderBonus(atk, ns.commanders, b) : b.scale;
    final defCmd =
        r.commanderEnabled ? _commanderBonus(def, ns.commanders, b) : b.scale;
    final res = resolveCombat(atk, def, atkTerr, defTerr, dist, b,
        atkCmdK: atkCmd, defCmdK: defCmd, dice: r.diceEnabled, rng: rng);
    atk.strength = math.max(0, atk.strength - res.lossAtk);
    def.strength = math.max(0, def.strength - res.lossDef);
    atk.fatigue = math.min(100, atk.fatigue + b.combatFatigue);
    def.fatigue = math.min(100, def.fatigue + b.combatFatigue);
    if (r.moraleEnabled) {
      def.morale = math.max(0,
          def.morale - (res.lossDef * b.moralePerCasualty ~/ math.max(1, def.maxStrength)));
      atk.morale = math.max(0,
          atk.morale - (res.lossAtk * b.moralePerCasualty ~/ math.max(1, atk.maxStrength)));
    }
    atk.status = UnitStatus.ready;
    def.status = UnitStatus.ready;
    ns.log.add('COMBAT $atkId->$defId atkLoss=${res.lossAtk} defLoss=${res.lossDef}');
  }

  // Phase 5: Attrition / Reorg
  if (r.attritionEnabled) _attritionReorg(ns, b, r);

  // Phase 6: Turn end (snapshot + event stream produced by `log`)
  ns.turn += 1;
  ns.log.add('TURN_END ${ns.turn}');
  return ns;
}

void _resolveSupply(GameState ns, BalanceData b) {
  final occ = <Axial, Side>{};
  for (final u in ns.units) {
    if (u.status != UnitStatus.eliminated) occ[u.pos] = u.side;
  }
  ns.supplyRates.clear();
  for (final side in Side.values) {
    final depots = ns.depots[side] ?? const <Axial>[];
    final blocked = <Axial>{};
    for (final e in occ.entries) {
      if (e.value != side) blocked.add(e.key);
    }
    final rates = supplyRates(ns.map, depots, blocked, b);
    for (final e in rates.entries) ns.supplyRates[e.key] = e.value;
    for (final u in ns.units) {
      if (u.side == side) u.supplyRate = rates[u.pos] ?? 0;
    }
  }
}

void _updateStates(GameState ns, BalanceData b, Ruleset r) {
  if (!r.moraleEnabled) return;
  final us = [...ns.units]..sort((a, c) => a.id.compareTo(c.id));
  for (final u in us) {
    if (u.status == UnitStatus.eliminated) continue;
    if (r.supplyEnabled && u.supplyRate < b.lowSupplyThreshold) {
      u.morale = math.max(0, u.morale - b.lowSupplyMoraleDrop);
    } else if (r.supplyEnabled) {
      u.morale = math.min(100, u.morale + b.supplyMoraleRecover);
    }
  }
}

void _applyMove(GameState ns, MoveCommand cmd, BalanceData b, Ruleset r) {
  final u = ns.findUnit(cmd.unitId);
  if (u == null || u.status == UnitStatus.eliminated) return;
  if (cmd.path.isEmpty) return;
  final occupied = <Axial>{};
  for (final o in ns.units) {
    if (o != u && o.status != UnitStatus.eliminated) occupied.add(o.pos);
  }
  final walk = ns.map.walkable(blocked: occupied);
  if (!walk.contains(u.pos)) return;

  final supplyFactor =
      (r.supplyEnabled && u.supplyRate < b.lowSupplyThreshold) ? 5000 : b.scale;
  final fatigueFactor = b.scale - u.fatigue * (b.scale ~/ 200);
  final budget = math.max(
      1,
      (u.stats.mobility * supplyFactor ~/ b.scale) *
          fatigueFactor ~/
          b.scale);

  int cost = 0;
  final usable = <Axial>[u.pos];
  for (final step in cmd.path) {
    if (!walk.contains(step) || occupied.contains(step)) break;
    final c = b.terrainMobility[ns.map.terrainAt(step)] ?? 1;
    if (cost + c > budget) break;
    cost += c;
    usable.add(step);
  }
  if (usable.length > 1) {
    u.pos = usable.last;
    u.fatigue = math.min(100, u.fatigue + cost);
    u.status = UnitStatus.ready;
    ns.log.add('MOVE ${u.id} -> ${u.pos} cost=$cost');
  }
}

void _attritionReorg(GameState ns, BalanceData b, Ruleset r) {
  final us = [...ns.units]..sort((a, c) => a.id.compareTo(c.id));
  for (final u in us) {
    if (u.status == UnitStatus.eliminated) continue;
    if (r.supplyEnabled && u.supplyRate >= b.lowSupplyThreshold) {
      u.fatigue = math.max(0, u.fatigue - b.fatigueRecover);
    }
    if (u.strength <= 0) {
      u.status = UnitStatus.eliminated;
      ns.log.add('ELIM ${u.id}');
      continue;
    }
    if (r.moraleEnabled && u.morale < b.routThreshold) {
      u.status = UnitStatus.routed;
      u.strength = math.max(0, u.strength - b.routStrengthLoss);
      ns.log.add('ROUT ${u.id}');
    } else if (u.status == UnitStatus.routed &&
        r.moraleEnabled &&
        u.morale >= b.routRecoveryMorale) {
      u.status = UnitStatus.ready;
    } else {
      u.status = UnitStatus.ready;
    }
  }
}

int _commanderBonus(Unit u, List<Commander> cmds, BalanceData b) {
  int best = b.scale;
  for (final c in cmds) {
    if (c.side != u.side) continue;
    if (hexDistance(c.pos, u.pos) <= b.commandRadius) {
      final k = b.scale + c.level * b.commanderPerLevel;
      if (k > best) best = k;
    }
  }
  return best;
}
