---
name: voxel-assets
description: 批量把新模型转成项目的 0.125 米体素并补齐外部信息（物品目录、观众评价）。用于新增/替换 assets 下的 glb/gltf、想把模型加入冒险遗物或展馆、检查体素资源是否合规，或用户提到「模型转体素」「批量导入模型」「遗物/展品登记」时。
---

# 体素资产流水线

把 `assets/<pack>/` 下的模型批量转成项目体素格式，产出可审查的 JSON，并补齐物品目录与观众评价。全程只用项目已有的 `VoxelModel` 采样，不引入新实现。

## 硬性约束

- 体素格固定 **0.125 m**（`Terrain.CELL_SIZE`），所有顶点必须落在格点上；`VoxelModel.sample_scene` 已保证，别绕开它。
- 代码、UI 与物品图标色只能用 [palette.gd](../../../palette.gd) 的 24 色（`Palette.*`）；体素面颜色来自源贴图采样，不手工改。确实需要新色先改 `docs/art/ART_BIBLE.md` 并说明。
- 每个模型必须通过 24 个直角朝向的一致性检查（格数、面数、面颜色、逆旋转复原）。
- 外部信息只写外形与来源：**不编造剧情、稀有度、价格**；价格、footprint、size 是玩法数值，按现有区间给建议并让用户确认。
- 采样候选格超过 24000 的模型会失败，先下调 `size` 或拆分模型。

## 选型

体素化会变成实心格子，挖松要求清掉 80% 的外露面，形状直接决定手感：

- **适合**：体块完整、转折少的物件——头骨、工具、武器、箱柜、书、盾牌，轮廓一眼能认。
- **不适合**：细长或弯曲的结构——骨架（长而弯的肋骨）、细桌腿、链条、绳网。它们在体素里只剩 1 格宽的窄缝，周围的土很难清干净，玩家会卡在最后 20%；确需使用就先简化源模型（加厚、去掉细枝）再导入。
- **巨大物件**：允许同一模型等比放大后另起一条目录记录（如 `chest` → `chest_large`，label「大箱子」）：`size` 取 1.5–3.0，footprint 按 `bounds_cells` 增大，价格按体积上调。不要改 0.125 米格，也不用另做模型；工具按目录逐条导出，同一场景的多个变体各出一份 JSON。
- 放大后仍要满足候选格上限，且 `bounds_cells` 最长边要放得进活动圈。

## 步骤

1. **放素材并留档**：模型放进 `assets/<pack>/`；在 `assets/<pack>/README.md` 补来源、许可、SHA256 和原始尺寸。不要改源模型几何。
2. **跑批量导出**：

   ```bash
   Godot --headless --path <项目目录> -s tools/voxelize_models.gd -- --pack assets/<pack>
   ```

   省略 `--pack` 时默认 `assets/adventure`。任何模型失败时退出码为 1。
3. **读结果**：`assets/<pack>/voxel/catalog.json`。每个模型必须 `ok: true`、`lattice: true`、`orientations.count: 24`，且 `orientations` 的 `cells/faces/palette_consistent` 全为 true。
4. **补外部信息**：`catalog.json` 的 `missing` 列出缺项。按缺项修改：
   - 物品目录 `adventure_items.gd` 的 `ITEMS`：`id`、`label`、`scene`、`size`（普通 1.0–1.25，巨物 1.5–3.0）、`footprint`（参考 `bounds_cells` 与同类物品，1–3 格；巨物可到 4–5）、`value`（现有遗物 520–800，巨物按体积上调）、`color`（`Palette.*`）。
   - 观众评价 `museum_visitor_comments.gd`：`NAMES` 加类别中文名，`REACTIONS` 加 **3 条**只描述外形/轮廓的短句（每条 ≤16 字，不写来历、稀有度、价格）。
   - `id` 与 `item_type` 必须一致，展馆按它匹配评价。
5. **重跑第 2 步**，直到 `missing` 为空；抽查 `voxel/<id>.json` 的 `cells` / `face_colors` / `palette` 与 `bounds_cells` 是否合理。
6. **验收**：

   ```bash
   Godot --headless --path <项目目录> -s tests/voxel_prop_assets_smoke.gd
   Godot --headless --path <项目目录> -s tests/orthogonal_voxel_smoke.gd
   Godot --headless --path <项目目录> -s tests/adventure_loot_smoke.gd
   Godot --headless --path <项目目录> -s tests/museum_visitors_smoke.gd
   ```

   新增物品若改变了掉落构成，补跑 `tests/world_smoke.gd` 与 `tests/activity_area_smoke.gd`。
7. **留档**：改了玩法数值或掉落规则，按现有格式在 `docs/implementation-log.md` 记一条（旧/新/原因/未完成）。

## 输出格式

`voxel/<id>.json`（`format: moon-voxel-v1`）：

| 字段 | 含义 |
| --- | --- |
| `id` / `label` / `source` | 物品 id、显示名、源模型路径 |
| `source_sha256` | 源文件哈希，用于溯源 |
| `target_size` | 采样目标最长边（米）；`target_size_source` 说明取自目录还是默认 1.25 |
| `registered` | 是否已在 `adventure_items.gd` 登记 |
| `counts` | `occupied` 占据格、`surface` 表面格、`interior` 闭合填充、`boundary_faces` 边界面 |
| `bounds_cells` | 旋转后包围盒（格坐标偏移与格数） |
| `palette` | 用到的调色板色（`#rrggbbaa`） |
| `cells` | `[x, y, z, "#rrggbbaa"]`，规范朝向下的占据格 |
| `face_colors` | `[x, y, z, side, "#rrggbbaa"]`，side 对应 `VoxelModel.STEPS` 顺序 |
| `lattice` / `orientations` | 格点与 24 朝向校验结果 |
| `comments_registered` | 该 id 是否已有观众评价 |
| `ok` | 以上校验的汇总 |

`catalog.json`（`moon-voxel-catalog-v1`）是索引，含 `models` 摘要和 `missing` 缺项清单。

生成的 `voxel/*.json` 是构建产物，可提交以便审查，也可按需忽略；但 `catalog.json` 的 `missing` 必须为空才算完成。
