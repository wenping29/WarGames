import 'hex.dart';

// Unit / commander domain model. Units use a component-style data class
// (composition, not inheritance) so mode switches can trim fields cheaply.

enum Side { blue, red }

enum UnitType { infantry, armor, artillery, motorized }

enum UnitStatus { ready, moving, engaged, routed, eliminated }

enum Terrain { plain, forest, hill, mountain, urban, water, impassable }

// 7-dimensional stat component (机动/火力/防护/侦察/补给/指挥/协同)
class Stats {
  final int mobility;
  final int firepower;
  final int protection;
  final int recon;
  final int supplyCap;
  final int command;
  final int coordination;
  const Stats({
    required this.mobility,
    required this.firepower,
    required this.protection,
    required this.recon,
    required this.supplyCap,
    required this.command,
    required this.coordination,
  });
}

class Unit {
  final String id;
  final Side side;
  final UnitType type;
  Axial pos;
  Stats stats;
  int strength;
  final int maxStrength;
  int morale; // 0..100
  int fatigue; // 0..100
  int supplyRate; // fixed-point 0..scale (set by supply solver)
  UnitStatus status;

  Unit({
    required this.id,
    required this.side,
    required this.type,
    required this.pos,
    required this.stats,
    required this.strength,
    required this.maxStrength,
    this.morale = 100,
    this.fatigue = 0,
    this.supplyRate = 0,
    this.status = UnitStatus.ready,
  });

  Unit clone() => Unit(
        id: id,
        side: side,
        type: type,
        pos: pos,
        stats: stats,
        strength: strength,
        maxStrength: maxStrength,
        morale: morale,
        fatigue: fatigue,
        supplyRate: supplyRate,
        status: status,
      );
}

class Commander {
  final String id;
  final Side side;
  final int level;
  Axial pos;
  int commandPoints;
  Commander({
    required this.id,
    required this.side,
    required this.level,
    required this.pos,
    this.commandPoints = 10,
  });

  Commander clone() => Commander(
        id: id,
        side: side,
        level: level,
        pos: pos,
        commandPoints: commandPoints,
      );
}
