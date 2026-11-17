# 旅行足迹 · 项目日志

> 这个文件既是**改动日志**，也是这个项目的**长期记忆**：最前面记录需求、约束、数据来源和工程结构，
> 后面按版本追加每次改动。以后任何人（包括 AI）接手，先读这里。

---

## 一、项目需求（长期有效）

### 1. 一句话目标

做一个**手机上的旅行足迹地图** App：把去过的省、市、国家在地图上点亮，随时看"我去过哪些地方"，
并能把这张地图存成图片 / 分享出去。

### 2. 背景

- 原项目是用户自己在 Android Studio 里写的 Flutter 应用（版本号 0.3.x），效果不理想：地图只是一个普通的地图控件，
  数据只有区县级的残缺数据，交互和视觉都离"想象中的样子"很远。
- 参考产品：**zuji.subsfast.com**（"我的足迹"）。它用 ECharts 画中国/世界地图，点亮省市区并统计数量，能导出图片。
- 因此本项目的目标是**彻底重构**：换掉原实现，按参考产品的体验重做，而不是在原代码上修补。

### 3. 交付形态（已与用户确认）

- **只做安卓 App**（Flutter，Android 单平台）。不做网页版、不部署站点、不做 iOS/桌面端。
- 版本号从 **0.1.0** 开始；每完成一个版本，用 git 提交并推送到
  `https://github.com/Gaiding2007/travel_footprint`（main 分支）。
- 每次改动都记录到本文件。

### 4. 第一版（0.1.0）必须有的能力

1. 省市两级中国地图：省级行政区边界 + 地级行政区边界，白色底图。
2. 全球国家/地区地图，可切换（国内 / 全球）。
3. 点亮交互：点省份 = 整省点亮/取消；放大到一定程度点城市 = 单个城市点亮/取消；点国家 = 点亮/取消。
4. 计数：`已点亮 N 省 M 市` / `已点亮 N 个国家和地区`，并展示总体进度。
5. 选择面板：省份列表（三态勾选、可展开逐市勾选）、国家列表、显示地名/仅看已选开关。
6. 存图与分享：把地图画面导出成图片存进相册，或走系统分享。
7. 本地保存：退出再进来自动恢复已点亮的地方。
8. 视觉风格贴近参考产品：白底、浅蓝点亮色、干净的地名标注、水印。

### 5. 第一版暂时不做

- 账号 / 云同步 / 多设备同步；社交、评论、足迹时间线；行程规划。
- iOS、Web、桌面端。
- 区县级（更细一层）地图；海外国家内部的行政区。
- 暗色模式、多语言。
- 应用商店上架所需的正式签名（0.1.0 用 debug 签名，后续版本再补）。

### 6. 硬约束

- **离线可用**：地图数据打包进 App，不依赖运行时联网。
- 只用 Flutter 官方能力 + `shared_preferences`，不引入重型第三方地图/图表库（原实现依赖 flutter_map 那套瓦片地图，已被替换）。
- 所有改动都要能通过 `flutter analyze`（当前 0 issue）和 `flutter test`。

---

## 二、技术备忘（环境、构建、数据）

### 1. 本机环境

| 项目 | 位置 / 版本 |
| --- | --- |
| Flutter | `D:\applications\Flutter`（3.38.4 stable，Dart 3.10.3） |
| JDK | `D:\applications\Android Studio\jbr`（21.0.8），构建前必须设 `JAVA_HOME` |
| Android SDK | `D:\applications\SDK`（platform 36 / build-tools 36.1.0） |
| 模拟器 | `emulator-5554`（AVD `Medium_Phone`） |
| git | `D:\applications\Git\cmd\git.exe` |

`flutter.bat` 在本机会卡在 `bin\cache\flutter.bat.lock`，而且它会 `git fetch --tags`（本机 hosts 把 github 指向 127.0.0.1 会失败）。
所以统一用下面的方式调用：

```powershell
$env:JAVA_HOME='D:\applications\Android Studio\jbr'
$env:FLUTTER_SUPPRESS_ANALYTICS='true'
& "D:\applications\Flutter\bin\cache\dart-sdk\bin\dart.exe" `
  "D:\applications\Flutter\bin\cache\flutter_tools.snapshot" `
  --no-version-check --suppress-analytics build apk --release
```

推送 GitHub（本机 schannel 不可用，需要 openssl 后端 + 清空代理变量）：

```powershell
$env:HTTP_PROXY=''; $env:HTTPS_PROXY=''; $env:ALL_PROXY=''
git -c http.sslBackend=openssl -c http.sslVerify=false -c credential.helper=manager push -u origin main
```

> ⚠️ 不要用 PowerShell 的 `Get-Content`/`Set-Content` 去改带中文的 Dart 源码（会按 GBK 读写把中文注释写坏、文件变成非法 UTF-8，
> 编辑器/分析器直接报 `Target of URI doesn't exist`）。改源码请用编辑器/AI 工具本身写文件。

### 2. 地图数据来源与构建

参考站用的是 ECharts 的 UTF8Encoding 压缩 GeoJSON，我们把它解码成自己的紧凑格式：

- 源文件（下载缓存，不入库）：`tools/cache/cn_geo.js`、`tools/cache/world_geo.js`、`tools/cache/index.js`（来自参考站静态分片）。
- 构建脚本：`tools/build_geo.mjs`（Node 22 运行）。
  - 解码规则：`encodeOffsets` 若为 `[x, y]`（一级数组）= Polygon 的单环偏移；若为 `[[x, y], ...]` = MultiPolygon，逐环解码。
  - zigzag 还原：`x = (code - 64) >> 1 ^ -(code & 1)` 累加后除以 `UTF8Scale || 1024`。
  - 世界国家做 Douglas-Peucker 简化（`WORLD_TOL = 0.03`），国内不简化。
- 产物（入库，App 直接读）：
  - `assets/geo/cn.json`：34 个省级行政区 + 372 个地级行政区，88,231 个坐标点。
  - `assets/geo/world.json`：236 个国家和地区，84,583 个坐标点。
- 坐标统一存"经纬度 × 10000"的整数（省体积）；运行时用等距圆柱投影换算成屏幕坐标：
  `x = (经度 + 180) * 1000`、`y = (90 - 纬度) * 1000`。
- 要素字段：`{ i: id, n: 简称, e: 全称, p: 父级 id, x/y: 标注点, b: 包围盒, r: 环数组 }`。

### 3. 工程结构

```
lib/
  main.dart                       启动、加载数据、加载本地足迹
  app_info.dart                   应用名 / 版本号 / 水印文案
  theme.dart                      配色与 Material3 主题
  data/shape.dart                 投影工具、Shape（多环多边形 + 命中判断）
  data/geo_data.dart              GeoData：省/市/国家索引、坐标反查（provinceAt / cityAt / countryAt）
  state/footprint_store.dart      已点亮集合、持久化（shared_preferences）、增删改通知
  map/map_transform_controller.dart  缩放/平移状态（纯数学，可单测）
  map/footprint_map.dart          地图绘制（Canvas 批绘制）+ 手势 + 点击命中
  screens/home_screen.dart        主界面：标题、国内/全球切换、地图卡片、概览卡、底部按钮
  widgets/selection_sheet.dart    底部升起的"选择城市 / 国家"面板
  services/export_service.dart    把地图卡片截图成 PNG
  services/media_service.dart     MethodChannel：存相册 / 系统分享
android/app/src/main/kotlin/.../MainActivity.kt   MediaStore 写相册 + ACTION_SEND 分享
tools/build_geo.mjs               地图数据构建脚本
tools/make_screenshots.py         把调试截图裁成 README 用的图片
docs/screenshots/                 README 截图
```

绘制策略：所有市拼成一条 Path 批绘制（白色填充 + 灰色细边界），已点亮的市单独一条 Path 填充 `#90CEFF`，
省界用更粗的 `#333` 描边；地名按包围盒去重、按面积优先、随缩放切换省名/市名；整个变换只做一次
`canvas.translate + canvas.scale`，因此缩放拖动很流畅。

---

## 三、版本记录

### 0.1.0 — 2026-11-17

**从零重构，第一个可用版本。**

#### 新增

- 全新 Flutter 安卓工程（`com.gaiding.travel_footprint`），替换掉原来的 0.3.x 实现；原实现保留在提交
  `chore: 存档重构前的旧版实现（0.3.12）` 里可回溯。
- 自带离线地图数据（省市 34+372，国家 236），无需联网。
- 国内地图：白色底 + 市级细边界 + 省级粗边界；点省份整省点亮，放大后点城市单市点亮；长按可直接点城市。
- 全球地图：236 个国家和地区，点击点亮，标注随缩放收敛，避免糊成一片。
- 顶部计数徽章（`已点亮 N 省 M 市` / `已点亮 N 个国家和地区`）、国内/全球切换、右上角菜单（清空全部、关于）。
- 地图下方"足迹概览"卡：省级/城市/国家三个数字 + 进度条（省 4/34、市 52/372 这种） + 已点亮地名标签。
- 底部选择面板：省份三态勾选（全选/部分/未选）、展开逐市勾选、"显示地名"、"仅看已选"、一键清空。
- 保存图片：把地图卡片（含计数与水印）按 3 倍像素导出 PNG，写入相册 `Pictures/TravelFootprint/`。
- 分享：调用系统分享面板发送刚才那张图。
- 本地持久化：已点亮的省/市/国家写在 `shared_preferences`，杀进程重进不丢。
- 单元测试：投影、数据解析与坐标命中、包围盒。

#### 交互细节

- 缩放范围：适屏比例 × 0.85 ~ × 45；双指缩放以手指中心为锚点；单指拖动有边界回弹限制。
- 倍率 ≥ 适屏 × 2.2 时进入"市级"模式：点击命中城市、标注切换为城市名。
- 北京/上海/天津/重庆/香港/澳门这些面积小的行政区优先显示名称。

#### 验证记录（emulator-5554 实测）

| 项目 | 结果 |
| --- | --- |
| 冷启动、加载数据 | 正常，首屏 0 省 0 市 |
| 点省份点亮 | 陕西 → `1 省 10 市`，整省变蓝 |
| 放大后点城市 | 兰州 → `32 市`，只有兰州变蓝 |
| 选择面板 | 34 个省行、三态勾选、展开河北显示 11 个市标签、切"仅看已选"正常 |
| 全球地图 | 236 国，点哈萨克斯坦 → `1 个国家和地区` |
| 保存图片 | 生成 `travel-footprint-20261117-123700.png`（1163×1432），相册可见 |
| 分享 | 弹出系统分享面板（Quick Share / Gmail / Photos…） |
| 重启恢复 | 杀进程重进，仍为 `1 省 11 市` |
| `flutter analyze` | No issues found |
| `flutter test` | 3 个用例全部通过 |

#### 已知问题 / 下一版计划

- 发布包目前用 debug 签名，正式发布前要生成自己的 keystore。
- 全球地图上下留白偏多（世界范围宽高比导致），考虑按区域裁剪或提供"聚焦某洲"。
- 国内/全球模式没有持久化（重进默认国内）。
- 首次进入没有引导页，只有概览卡上的一行提示。
- 点亮单个城市时，低倍率下蓝色区域很小，考虑给"部分点亮"的省加一层浅色底。
- 没有暗色模式、没有 iOS/Web。

---

## 四、版本记录模板（下次照这个写）

```
### x.y.z — YYYY-MM-DD
#### 新增
#### 修改
#### 修复
#### 验证记录
#### 已知问题
```
