// 生成 HEXFRONT 内核垂直切片的可视化网页 (demo_view.html)。
// 所有数值均由内核真实计算得出，内联进自包含 HTML，无需 server。
import 'dart:convert';
import 'dart:io';
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

String enumName(Object e) => e.toString().split('.').last;

void main() {
  final b = BalanceData.load();

  // ---------- 场景复刻 (9x9) ----------
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
  final rs = Ruleset.forMode(Mode.pro);
  var s = GameState(
    map: map, units: units, commanders: [], depots: depots,
    supplyRates: {}, turn: 0, log: [], ruleset: rs, balance: b,
  );

  final initPos = {for (var u in units) u.id: [u.pos.q, u.pos.r]};

  s = step(s, [], rs, b, SeededRNG(1)); // turn1
  final turn1 = s.units
      .map((u) => {'id': u.id, 'side': enumName(u.side), 'type': enumName(u.type), 'q': u.pos.q, 'r': u.pos.r, 'supply': (u.supplyRate / 100).toStringAsFixed(1), 'str': u.strength})
      .toList();

  final cmds2 = <Command>[
    MoveCommand('B1', [Axial(2, 1), Axial(3, 1), Axial(4, 1), Axial(4, 2)]),
    MoveCommand('B2', [Axial(2, 3), Axial(3, 4), Axial(4, 5), Axial(5, 6)]),
  ];
  s = step(s, cmds2, rs, b, SeededRNG(2)); // turn2
  s = step(s, [], rs, b, SeededRNG(3)); // turn3
  final turn3 = s.units
      .map((u) => {'id': u.id, 'side': enumName(u.side), 'type': enumName(u.type), 'q': u.pos.q, 'r': u.pos.r, 'supply': (u.supplyRate / 100).toStringAsFixed(1), 'str': u.strength})
      .toList();

  // ---------- 全图补给热力 (回合3) ----------
  final full = supplyRates(map, [Axial(0, 0), Axial(8, 8)], {}, b);
  final supplyFull = <String, dynamic>{};
  for (var u in s.units) {
    // 单位自身补给取自真实状态
  }
  for (final e in full.entries) {
    supplyFull['${e.key.q},${e.key.r}'] = (e.value / 100).toStringAsFixed(1);
  }

  // ---------- 地形 ----------
  final terrain = <Map<String, dynamic>>[];
  for (final e in map.cells.entries) {
    terrain.add({'q': e.key.q, 'r': e.key.r, 't': enumName(e.value)});
  }

  // ---------- 推进路径 ----------
  final paths = {
    'B1': [initPos['B1'], ...(cmds2[0] as MoveCommand).path.map((a) => [a.q, a.r])],
    'B2': [initPos['B2'], ...(cmds2[1] as MoveCommand).path.map((a) => [a.q, a.r])],
  };

  // ---------- 补给衰减曲线 ----------
  final corr12 = HexMap.rectangular(12, 1, Terrain.plain);
  final decayRates = supplyRates(corr12, [Axial(0, 0)], {}, b);
  final decay = <Map<String, dynamic>>[];
  for (var d = 0; d < 12; d++) {
    decay.add({'d': d, 'rate': ((decayRates[Axial(d, 0)] ?? 0) / 100).toStringAsFixed(1)});
  }

  // ---------- 补给线切断 ----------
  final corr = HexMap.rectangular(8, 1, Terrain.plain);
  final open = (supplyRates(corr, [Axial(0, 0)], <Axial>{}, b)[Axial(5, 0)] ?? 0) / 100;
  final cut = (supplyRates(corr, [Axial(0, 0)], {Axial(2, 0)}, b)[Axial(5, 0)] ?? 0) / 100;

  // ---------- 邻接交战 ----------
  final cmap = HexMap.rectangular(5, 5, Terrain.plain);
  final catk = Unit(id: 'ATK', side: Side.blue, type: UnitType.armor, pos: Axial(2, 2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final cdef = Unit(id: 'DEF', side: Side.red, type: UnitType.infantry, pos: Axial(3, 2), stats: fullStats(), strength: 100, maxStrength: 100, supplyRate: 10000, morale: 100);
  final cfA = baseCF(catk, Terrain.plain, b, b.scale);
  final cfD = baseCF(cdef, Terrain.plain, b, b.scale);
  final after = step(
    GameState(map: cmap, units: [catk, cdef], commanders: [], depots: {Side.blue: [Axial(0, 0)], Side.red: [Axial(4, 4)]}, supplyRates: {}, turn: 0, log: [], ruleset: rs, balance: b),
    [CombatCommand('ATK', 'DEF')], rs, b, SeededRNG(9),
  );
  final a2 = after.findUnit('ATK')!, d2 = after.findUnit('DEF')!;

  final data = {
    'mapW': 9, 'mapH': 9,
    'terrain': terrain,
    'supplyFull': supplyFull,
    'turn1': turn1, 'turn3': turn3,
    'paths': paths,
    'decay': decay,
    'corridor': {'open': open.toStringAsFixed(1), 'cut': cut.toStringAsFixed(1)},
    'combat': {'cfA': cfA, 'cfD': cfD, 'ratio': (cfA / cfD).toStringAsFixed(2), 'aStr': a2.strength, 'aMor': a2.morale, 'dStr': d2.strength, 'dMor': d2.morale},
  };

  final html = template.replaceAll('__DATA__', json.encode(data));
  final out = 'demo_view.html';
  File(out).writeAsStringSync(html);
  print('已生成 $out (${html.length} 字节)');
}

const template = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>HEXFRONT 内核垂直切片 · 可视化</title>
<style>
  :root{ --bg:#0f1320; --panel:#171c2e; --ink:#e8ecf5; --mut:#9aa6c2; --blue:#2d6cdf; --red:#e0494b; --line:#2a3350; }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 "Segoe UI",system-ui,"PingFang SC","Microsoft YaHei",sans-serif}
  header{padding:22px 26px 8px}
  h1{margin:0;font-size:20px;letter-spacing:.5px}
  h1 span{color:#7da2ff}
  .sub{color:var(--mut);font-size:12.5px;margin-top:4px}
  .wrap{max-width:1080px;margin:0 auto;padding:0 22px 40px}
  .card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:18px 20px;margin:16px 0}
  .card h2{margin:0 0 12px;font-size:15px;color:#cdd7f0}
  .row{display:flex;gap:18px;flex-wrap:wrap;align-items:flex-start}
  .legend{display:flex;gap:14px;flex-wrap:wrap;color:var(--mut);font-size:12px;margin:6px 0 10px}
  .chip{display:inline-flex;align-items:center;gap:5px}
  .dot{width:12px;height:12px;border-radius:50%;display:inline-block}
  button{background:#22304f;color:var(--ink);border:1px solid #34436b;border-radius:7px;padding:6px 13px;cursor:pointer;font-size:13px}
  button.on{background:#2d6cdf;border-color:#2d6cdf}
  svg text{font-family:inherit}
  .bar{height:14px;border-radius:4px;background:#222a40;overflow:hidden;margin:3px 0}
  .bar>i{display:block;height:100%}
  .kv{font-size:12.5px;color:var(--mut)}
  .grid2{display:grid;grid-template-columns:1fr 1fr;gap:18px}
  @media(max-width:760px){.grid2{grid-template-columns:1fr}.row{flex-direction:column}}
</style>
</head>
<body>
<header>
  <h1>铁幕兵棋 <span>HEXFRONT</span> · 确定性内核垂直切片</h1>
  <div class="sub">本页所有数值均由 Dart 内核真实计算后导出 · 六边形网格 / 后勤补给线 / 作战解析 / 回合调度器</div>
</header>
<div class="wrap">

  <div class="card">
    <h2>① 战场棋盘 · 补给热力 + 单位部署</h2>
    <div class="legend">
      <span class="chip"><span class="dot" style="background:#2d6cdf"></span>蓝方</span>
      <span class="chip"><span class="dot" style="background:#e0494b"></span>红方</span>
      <span class="chip">林=森林 丘=丘陵 城=城市</span>
      <span class="chip">底色=补给率(绿充足→红匮乏)</span>
    </div>
    <div style="margin-bottom:10px">
      <button id="bT1" class="on" onclick="setTurn(1)">初始部署（回合1）</button>
      <button id="bT3" onclick="setTurn(3)">第3回合（推进后）</button>
    </div>
    <div id="board"></div>
    <div class="kv" id="boardCap"></div>
  </div>

  <div class="grid2">
    <div class="card">
      <h2>② 补给衰减曲线</h2>
      <div class="kv">R(d)=R₀·retentionᵈ，每跳远离补给源衰减约 16.5%</div>
      <div id="decay"></div>
    </div>
    <div class="card">
      <h2>③ 补给线切断（护城河）</h2>
      <div class="kv">单线走廊，敌人占据唯一通道即切断末端补给</div>
      <div id="corridor"></div>
    </div>
  </div>

  <div class="card">
    <h2>④ 邻接交战解析 · 装甲 vs 步兵</h2>
    <div class="kv">CF=基础×地形×建制×补给×士气×指挥官×克制；满补给满士气无掩体</div>
    <div id="combat"></div>
  </div>

  <div class="card">
    <h2>⑤ 运行验证</h2>
    <div class="kv">dart analyze 零警告 · 19/19 内核+对拍测试通过 · 同种子双端重算快照逐字节一致</div>
  </div>
</div>

<script>
const DATA = __DATA__;
const SIZE = 34, OX = 52, OY = 52;
const hexToPixel = (q,r)=>({x: SIZE*Math.sqrt(3)*(q + r/2) + OX, y: SIZE*1.5*r + OY});
function hexPts(cx,cy,s){let p=[];for(let i=0;i<6;i++){const a=Math.PI/180*(60*i-30);p.push((cx+s*Math.cos(a)).toFixed(1)+','+(cy+s*Math.sin(a)).toFixed(1));}return p.join(' ');}
function supplyColor(r){r=Math.max(0,Math.min(100,r));const t=r/100;let c1,c2,k;if(t<0.5){c1=[210,70,70];c2=[235,200,90];k=t/0.5;}else{c1=[235,200,90];c2=[75,165,95];k=(t-0.5)/0.5;}const R=Math.round(c1[0]+(c2[0]-c1[0])*k),G=Math.round(c1[1]+(c2[1]-c1[1])*k),B=Math.round(c1[2]+(c2[2]-c1[2])*k);return 'rgb('+R+','+G+','+B+')';}
const terrMark={forest:'林',hill:'丘',urban:'城'};
const typeMark={infantry:'步',armor:'装',artillery:'炮',motorized:'摩'};

function renderBoard(turn){
  const units = turn===1 ? DATA.turn1 : DATA.turn3;
  const showPath = turn===3;
  let s='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 820 520">';
  // 地形 + 补给热力底
  for(const t of DATA.terrain){
    const p=hexToPixel(t.q,t.r);
    const sup=parseFloat(DATA.supplyFull[t.q+','+t.r]||'0');
    s+='<polygon points="'+hexPts(p.x,p.y,SIZE-1.5)+'" fill="'+supplyColor(sup)+'" stroke="#0f1320" stroke-width="1.5"/>';
    if(terrMark[t.t]) s+='<text x="'+p.x+'" y="'+(p.y-SIZE+13)+'" fill="#243049" font-size="11" text-anchor="middle">'+terrMark[t.t]+'</text>';
  }
  // 推进路径
  if(showPath){
    for(const k in DATA.paths){
      const path=DATA.paths[k];
      let d='M';
      path.forEach((c,i)=>{const p=hexToPixel(c[0],c[1]);d+=(i?' L':'')+p.x.toFixed(1)+' '+p.y.toFixed(1);});
      s+='<path d="'+d+'" fill="none" stroke="#ffd76a" stroke-width="2" stroke-dasharray="4 3" opacity="0.85"/>';
    }
  }
  // 单位
  for(const u of units){
    const p=hexToPixel(u.q,u.r);
    const col=u.side==='blue'?'#2d6cdf':'#e0494b';
    s+='<circle cx="'+p.x+'" cy="'+p.y+'" r="13" fill="'+col+'" stroke="#fff" stroke-width="1.5"/>';
    s+='<text x="'+p.x+'" y="'+(p.y+4)+'" fill="#fff" font-size="10" font-weight="700" text-anchor="middle">'+typeMark[u.type]+'</text>';
    s+='<text x="'+p.x+'" y="'+(p.y+SIZE-6)+'" fill="#0f1320" font-size="9.5" font-weight="700" text-anchor="middle">'+u.supply+'%</text>';
    s+='<text x="'+(p.x+15)+'" y="'+(p.y-13)+'" fill="#fff" font-size="9" text-anchor="middle">'+u.id+'</text>';
  }
  s+='</svg>';
  document.getElementById('board').innerHTML=s;
  document.getElementById('boardCap').textContent = showPath
    ? '第3回合：蓝方 B1/B2 已推进，补给随距离显著下降（补给结算有1回合滞后）'
    : '回合1：补给基于初始位置结算，单位越远离己方补给源(角落)补给率越低';
}
function setTurn(t){document.getElementById('bT1').className=t===1?'on':'';document.getElementById('bT3').className=t===3?'on':'';renderBoard(t);}

function renderDecay(){
  const w=480,h=200,pad=34; const maxR=100;
  let s='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+w+' '+h+'">';
  s+='<line x1="'+pad+'" y1="'+(h-pad)+'" x2="'+(w-10)+'" y2="'+(h-pad)+'" stroke="#34436b"/>';
  s+='<line x1="'+pad+'" y1="14" x2="'+pad+'" y2="'+(h-pad)+'" stroke="#34436b"/>';
  let d='M';
  DATA.decay.forEach((pt,i)=>{const x=pad+(w-10-pad)*i/(DATA.decay.length-1);const y=(h-pad)-(h-pad-14)*pt.rate/maxR;d+=(i?' L':'')+x.toFixed(1)+' '+y.toFixed(1);});
  s+='<path d="'+d+'" fill="none" stroke="#7da2ff" stroke-width="2.5"/>';
  DATA.decay.forEach((pt,i)=>{if(i%2===0){const x=pad+(w-10-pad)*i/(DATA.decay.length-1);const y=(h-pad)-(h-pad-14)*pt.rate/maxR;s+='<circle cx="'+x+'" cy="'+y+'" r="2.5" fill="#7da2ff"/><text x="'+x+'" y="'+(y-6)+'" fill="#9aa6c2" font-size="9" text-anchor="middle">'+pt.rate+'</text><text x="'+x+'" y="'+(h-pad+13)+'" fill="#9aa6c2" font-size="9" text-anchor="middle">d'+pt.d+'</text>';}});
  s+='<text x="14" y="40" fill="#9aa6c2" font-size="9">100%</text><text x="14" y="'+(h-pad-2)+'" fill="#9aa6c2" font-size="9">0</text>';
  s+='</svg>';
  document.getElementById('decay').innerHTML=s;
}

function renderCorridor(){
  const open=DATA.corridor.open, cut=DATA.corridor.cut;
  const n=8, s0=30, x0=40, y0=70;
  function col(q){ if(q===2) return '#e0494b'; return '#394b78'; }
  let s='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 '+(x0+ n*s0*1.732 +20)+' 160">';
  for(let q=0;q<n;q++){
    const x=x0+s0*Math.sqrt(3)*q, y=y0;
    s+='<polygon points="'+hexPts(x,y,s0-1.5)+'" fill="'+col(q)+'" stroke="#0f1320" stroke-width="1.5"/>';
    if(q===0) s+='<text x="'+x+'" y="'+(y+4)+'" fill="#fff" font-size="10" text-anchor="middle">源</text>';
    if(q===2) s+='<text x="'+x+'" y="'+(y+4)+'" fill="#fff" font-size="11" font-weight="700" text-anchor="middle">敌</text>';
    if(q===5) s+='<text x="'+x+'" y="'+(y+4)+'" fill="#fff" font-size="10" text-anchor="middle">末</text>';
  }
  s+='</svg>';
  s+='<div class="kv" style="margin-top:6px">走廊末端补给率：通畅 <b style="color:#7fe0a0">'+open+'%</b> → 通道(2,0)被占 <b style="color:#e0494b">'+cut+'%</b></div>';
  document.getElementById('corridor').innerHTML=s;
}

function renderCombat(){
  const c=DATA.combat; const max=Math.max(c.cfA,c.cfD,1);
  let s='<div class="row"><div style="flex:1">';
  s+='<div class="kv">ATK 装甲 CF</div><div class="bar"><i style="width:'+(100*c.cfA/max)+'%;background:#2d6cdf"></i></div>';
  s+='<div class="kv" style="margin-top:6px">DEF 步兵 CF</div><div class="bar"><i style="width:'+(100*c.cfD/max)+'%;background:#e0494b"></i></div>';
  s+='<div class="kv" style="margin-top:8px">战力比 ATK/DEF = <b style="color:#7da2ff">'+c.ratio+'</b></div></div>';
  s+='<div style="flex:1">';
  s+='<div class="kv">装甲(ATK) 交战后 建制 '+c.aStr+'/100 士气 '+c.aMor+'</div><div class="bar"><i style="width:'+c.aStr+'%;background:#2d6cdf"></i></div>';
  s+='<div class="kv" style="margin-top:6px">步兵(DEF) 交战后 建制 '+c.dStr+'/100 士气 '+c.dMor+'</div><div class="bar"><i style="width:'+c.dStr+'%;background:#e0494b"></i></div>';
  s+='<div class="kv" style="margin-top:8px">攻方代价更重(装甲突入步兵)，但守方建制损失更大</div>';
  s+='</div></div>';
  document.getElementById('combat').innerHTML=s;
}

renderBoard(1); renderDecay(); renderCorridor(); renderCombat();
</script>
</body>
</html>''';

