# numen-lua

一个用 Lua（LuaJIT）编写的自然语言计算与换算引擎。支持单位换算、货币汇率换算、百分比、小费、日期时间计算、中文大写金额等，并提供命令行工具和 Rime 输入法集成。

## 功能概览

- **四则运算**：`1 + 2 * 3`、`(2 + 3) * 4`、`2^10`，容忍未闭合括号（适合边输入边出结果的场景）
- **数学函数**：`sin(pi / 2)`、`sqrt(2)`、`log(2, 8)`、`avg(1, 2, 3)`、`5!`、`random(1, 100)` 等，另有常量 `pi`、`e`
- **单位换算**：长度、质量、时间、数据、速度、数据速率、功率，支持 `km/h`、`MB/s` 等复合单位
- **货币换算**：基于 JSON 汇率文件（EUR 基准，fawazahmed0/currency-api 格式），支持符号（`$` `¥` `€` `£`）、别名（`rmb`、`usd`）和汇率表中的任意币种（如 `thb`）
- **百分比**：`15% of 490`、`$55 + 25% tip`、`100 + 10%`（同时给出"相对"和"字面"两种歧义候选）
- **日期时间计算**：`date + 35day`、`12:30 + 5h`、`26-11-15 + 1d`、`now`、`today`，以及 `to date` / `to time` / `to datetime` 类型转换
- **多候选展示**：一个输入可产生多个候选结果，如相近单位（`1 kg` → `1000 g`、`2 斤`）、计算过程、人民币中文大写金额（`壹佰贰拾叁元肆角伍分`）

## 项目结构

这是一个 lde monorepo，包含三个包：

| 包 | 说明 |
|---|---|
| `packages/numen-core` | 核心引擎：词法分析、解析、求值、单位与汇率、结果格式化 |
| `packages/numen-cli` | 命令行工具 / 交互式 REPL |
| `packages/numen-rime` | Rime 输入法 Lua translator（前缀 `V` 触发计算） |

汇率文件默认读取 `./rates.json`，也可用环境变量 `NUMEN_RATES_PATH` 指定。

## 使用示例

```
> 1 + 2 * 3
  7

> 1 mile to km
  1.609344 km
  1 mile to km = 1.609344 km

> 1usd to rmb
  ¥6.70
  1 usd to cny = ¥6.70

> 15% of 490
  73.5

> $55 + 25% tip
  $68.75 (with tip)

> 100 + 10%
  110
  100.1

> today + 35d
  2026-11-08

> 12:30 + 90min
  14:00

> 123.45 rmb
  ¥123.45
  一百二十三元四角五分
  壹佰贰拾叁元肆角伍分

> 100 mbps to MB/s
  12.5 MB/s

> 100 km/h * 2 h
  200 km

> sin(pi / 6) * 2
  1

> log(2, 8)
  3

> avg(1, 2, 3)
  2

> 5! + 2^10
  1144
```

说明：

- 单独输入货币金额时，会按汇率自动换算为基准货币（默认人民币，可配置）
- 日期字面量：`2026-11-15`、`26-11-15`（两位年补 2000）、`-11-15`（当年 11 月 15 日）

## 支持的数学函数

| 函数 | 说明 |
|---|---|
| `sin` `cos` `tan` `asin` `acos` `atan` | 三角函数（弧度） |
| `sinh` `cosh` `tanh` | 双曲函数 |
| `atan2(y, x)` | 返回点 (x, y) 相对于 x 轴的逆时针角度，能正确处理 x = 0 的边界情况 |
| `deg(x)` / `rad(x)` | 弧度转角度 / 角度转弧度 |
| `exp(x)` / `sqrt(x)` | e^x / 平方根 |
| `log(y, x)` | 以 y 为底 x 的对数（换底公式） |
| `loge(x)` / `log10(x)` | 以 e / 10 为底的对数 |
| `avg(...)` / `var(...)` | 平均值 / 方差 |
| `fact(x)` | 阶乘，也可写成后缀形式 `5!` |
| `ldexp(x, y)` | 返回 x * 2^y |
| `frexp(x)` | 返回 `m * 2^e` 形式的文本，使得 x = m * 2^e |
| `random([m [, n]])` | 随机数：无参返回 0-1 小数；一个参数返回 1-m；两个参数返回 m-n（别名 `rdm`） |

常量：`pi`、`e`。乘方运算符 `^` 为右结合（`2^3^2` = 512），负号优先级低于 `^`（`-2^2` = -4）。

## 支持的单位

### 长度（基准：米）

| 单位 | 别名 |
|---|---|
| m（米） | `m` `meter` `米` |
| km（千米） | `km` `kilometer` `千米` `公里` |
| cm（厘米） | `cm` `centimeter` `厘米` |
| mm（毫米） | `mm` `millimeter` `毫米` |
| mi（英里） | `mi` `mile` `英里` |
| yd（码） | `yd` `yard` `码` |
| ft（英尺） | `ft` `foot` `feet` `英尺` |
| in（英寸） | `inch` `inches` `英寸` |

### 质量（基准：克）

| 单位 | 别名 |
|---|---|
| g（克） | `g` `gram` `克` |
| kg（千克） | `kg` `kilogram` `千克` `公斤` |
| t（吨） | `t` `ton` `tonne` `吨` |
| lb（磅） | `lb` `lbs` `pound` `磅` |

展示用中文单位：`斤`（500g）、`两`（50g）、`钱`（5g）、`担`（仅出现在"相近单位"候选中，不参与输入解析）。

### 时间（基准：秒）

| 单位 | 别名 |
|---|---|
| s（秒） | `s` `sec` `second` `秒` |
| min（分钟） | `min` `minute` `分钟`（时长语境下 `m` 也表示分钟） |
| h（小时） | `h` `hr` `hour` `小时` |
| day（天） | `d` `day` `天` `日` |

### 数据（基准：字节）

| 单位 | 别名 | 进位 |
|---|---|---|
| bit | `bit` | 1 B = 8 bit |
| B（字节） | `b` `byte` | — |
| KB / MB / GB / TB | `kb` `mb` `gb` `tb` | 默认 1000，可用 `binary_bytes` 切换为 1024 |
| KiB / MiB / GiB / TiB | `kib` `mib` `gib` `tib` | 1024（固定） |

### 速度（基准：米/秒）

| 单位 | 别名 |
|---|---|
| m/s | `mps` |
| km/h | `kmh` `kph` |
| mph | `mph` |

### 数据速率（基准：字节/秒）

| 单位 | 别名 |
|---|---|
| kbps | `kbps` |
| mbps | `mbps` |
| gbps | `gbps` |

### 功率（基准：瓦）

| 单位 | 别名 |
|---|---|
| W（瓦） | `w` `watt` |
| kW（千瓦） | `kw` |

### 货币

内置别名：`rmb` `cny` `yuan` `¥`（人民币）、`$` `usd` `dollar`（美元）、`€` `eur`（欧元）、`£` `gbp`（英镑）、`jpy` `yen`、`hkd`、`krw`、`aud`、`cad`、`chf`、`sgd`。此外，`rates.json` 中出现的任意币种代码（如 `thb`）都会自动可用。汇率文件采用 [fawazahmed0/currency-api](https://github.com/fawazahmed0/exchange-api) 格式（EUR 基准）。

## Lua API

```lua
local numen = require("numen-core")

local core = numen.Core.new({
    base_currency = "cny",           -- 基准货币（默认 cny）
    auto_convert_currency = true,    -- 裸货币金额自动换算为基准货币（默认开）
    implicit_day = true,             -- `date + 1` 按"天"计算（默认开）
    binary_bytes = false,            -- KB/MB/GB/TB 按 1024 进位（默认 1000）
    rates_path = "rates.json",       -- 汇率文件路径；也可直接传 rates = {...} 表
    now = { year = 2026, month = 10, day = 4, hour = 12, min = 0, sec = 0 }, -- 固定时钟（测试用）
})

local cands, err = core:evaluate("1usd to rmb")

local present = numen.Present.new({
    date_formats = { "Y-m-d", "Y年m月d日" },
    time_formats = { "H:M", "H:M:S" },
    datetime_formats = { "Y-m-d H:M" },
    rmb_cn = true,        -- 人民币结果附加中文金额候选（默认开）
    nearby_units = true,  -- 数量结果附加相近单位候选（默认开）
})
for _, line in ipairs(present:format_candidates(cands)) do
    print(line)
end
```

## Rime 输入法集成

`numen-rime` 提供 Lua translator，可在 Rime 中以 `cC` 前缀触发计算（如 `cC1usd to rmb`）。在方案中配置：

```yaml
recognizer/patterns/numen: "^cC.*"
translators: [lua_translator@numen]
processors: [lua_processor@numen]   # 可选：cC 模式下空格不上屏
filters: [lua_filter@numen]         # 可选：cC 模式下候选项序号用希腊字母（α β γ…），避免与数值混淆

numen:
  tips: "计算"
  show_prefix: false   # 是否在编辑区显示触发前缀（默认不显示，候选 preedit 只保留表达式）
  rates_path: "rates.json"
  base_currency: "cny"
  auto_convert_currency: true
  implicit_day: true
  date_formats: ["Y-m-d", "Y年m月d日"]
  time_formats: ["H:M", "H:M:S"]
  datetime_formats: ["Y-m-d H:M"]
  binary_bytes: true
  rmb_cn: true
  nearby_units: true
```

前缀从 `recognizer/patterns/numen`（或 `recognizer/patterns/calculator`）的正则中提取字面前缀，如 `"^cC.*"` → `cC`。

按键行为：空格写入输入串、回车上屏当前高亮候选、Tab / Shift+Tab 移动高亮。

## 鸣谢

- 数学函数集的设计参考自 Rime 计算器插件 [super_calculator.lua](https://github.com/ChaosAlphard)，原作者 [@ChaosAlphard](https://github.com/ChaosAlphard)，贡献者 [@DeepChirp](https://github.com/DeepChirp)。
- 汇率数据格式来自 [fawazahmed0/currency-api](https://github.com/fawazahmed0/exchange-api)。
