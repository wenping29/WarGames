# 铁幕兵棋 HEXFRONT — 长期项目记忆

## 项目定位
硬核兵棋策略手游（对标 WitE2 二战东线）。技术栈：**Dart 内核 + Flutter 客户端 + Go 服务端**（设计文档）。免费+内购（仅副本/外观，禁 pay-to-win）。当前仅有设计文档与原型，**尚无业务代码**。

## 关键未决 / 风险（来自 项目分析报告.md）
- **平台定位矛盾**：多数文档写「移动+PC 跨端」，但开发设计文档改为「仅移动端，PC 推到 P3+」，无任何说明，需向用户澄清。
- 两份 md 文档（草案 v0.1 / 产品设计文档 v1.0）高度冗余，建议合并。
- Q4 美术风格、Q5 团队/工期 从未评估；技术路线图停在 v0.1。

## 已落地代码
- `D:/Project/Wargames/hexfront_core`：P0 确定性仿真内核（纯 Dart，无 Flutter 依赖）。`dart analyze` 零警告，19/19 自包含测试通过。运行：`dart pub get` → `dart run test/run_tests.dart` → `dart run bin/main.dart`。
- 环境：已装 Dart SDK 3.11.1；Go 未装（服务端 Go 实现待定）。

## 用户偏好 / 协作
- 当前会话选定「吴八哥 / senior-developer」专家，偏好交付可运行、可验证代码（小步快跑、写→验→报）。
- 默认中文交流。
