// Deterministic seeded RNG (mulberry32).
// Do NOT use dart:math Random — its output is not guaranteed stable across platforms.
// All randomness in the simulation must flow through SeededRNG so replays/对拍 are exact.

class SeededRNG {
  int _state;

  SeededRNG(int seed) : _state = seed & 0xFFFFFFFF;

  // mulberry32
  int nextUint32() {
    _state = (_state + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _state;
    t = ((t ^ (t >>> 15)) * 0x0001B129) & 0xFFFFFFFF;
    t = (t ^ (t >>> 13)) & 0xFFFFFFFF;
    t = ((t ^ (t >>> 8)) * 0x00009E37) & 0xFFFFFFFF;
    t = (t ^ (t >>> 16)) & 0xFFFFFFFF;
    return t & 0xFFFFFFFF;
  }

  int nextInt(int max) => (max <= 0) ? 0 : nextUint32() % max;

  // fixed-point fraction in [0, scale]
  int nextFixed(int scale) => (nextUint32() * scale) ~/ 0xFFFFFFFF;

  // derive an independent deterministic sub-stream without consuming the parent unpredictably
  SeededRNG fork(int salt) =>
      SeededRNG((_state ^ ((salt * 0x9E3779B1) & 0xFFFFFFFF)) & 0xFFFFFFFF);
}
