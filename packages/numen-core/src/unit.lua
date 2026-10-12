--- Physical units, currency aliases and exchange-rate handling.
--- Rates are loaded from a JSON file (fawazahmed0/currency-api format,
--- base EUR): `{"date": "...", "eur": {"cny": 7.5, ...}}`.

local json = require("numen-core.jsonlite")

local M = {}

-- Dimension helpers: a dim is a map of exponents, e.g. {l=1} length,
-- {m=1} mass, {t=1} time, {d=1} data, {p=1} power, {l=1,t=-1} speed.
local Dim = {}
M.Dim = Dim

local DIM_KEYS = { "l", "m", "t", "d", "p" }

Dim.NONE = { l = 0, m = 0, t = 0 }
Dim.LENGTH = { l = 1 }
Dim.MASS = { m = 1 }
Dim.TIME = { t = 1 }
Dim.DATA = { d = 1 }
Dim.POWER = { p = 1 }
Dim.SPEED = { l = 1, t = -1 }
Dim.DATA_RATE = { d = 1, t = -1 }

function Dim.mul(a, b)
  local r = {}
  for _, k in ipairs(DIM_KEYS) do
    r[k] = (a[k] or 0) + (b[k] or 0)
  end
  return r
end

function Dim.div(a, b)
  local r = {}
  for _, k in ipairs(DIM_KEYS) do
    r[k] = (a[k] or 0) - (b[k] or 0)
  end
  return r
end

function Dim.eq(a, b)
  for _, k in ipairs(DIM_KEYS) do
    if (a[k] or 0) ~= (b[k] or 0) then
      return false
    end
  end
  return true
end

function Dim.is_none(a)
  return Dim.eq(a, Dim.NONE)
end

---@class UnitDef
---@field dim table
---@field factor number value of 1 unit in base units of its dim
---@field label string
---@field aliases string[]

-- 十进制/二进制字节单位的可切换进位（见 M.set_binary_bytes）
local BYTE_SCALE = 1000
local BYTE_UNITS = {} -- 需要随进位调整的十进制字节单位

---@type UnitDef[]
M.UNITS = {
  -- length (base: m)
  { dim = Dim.LENGTH, factor = 1, label = "m", aliases = { "m", "meter", "meters", "米" } },
  { dim = Dim.LENGTH, factor = 1000, label = "km", aliases = { "km", "kilometer", "kilometers", "千米", "公里" } },
  { dim = Dim.LENGTH, factor = 0.01, label = "cm", aliases = { "cm", "centimeter", "centimeters", "厘米" } },
  { dim = Dim.LENGTH, factor = 0.001, label = "mm", aliases = { "mm", "millimeter", "millimeters", "毫米" } },
  { dim = Dim.LENGTH, factor = 1609.344, label = "mi", aliases = { "mi", "mile", "miles", "英里" } },
  { dim = Dim.LENGTH, factor = 0.9144, label = "yd", aliases = { "yd", "yard", "yards", "码" } },
  { dim = Dim.LENGTH, factor = 0.3048, label = "ft", aliases = { "ft", "foot", "feet", "英尺" } },
  { dim = Dim.LENGTH, factor = 0.0254, label = "in", aliases = { "inch", "inches", "英寸" } },
  -- mass (base: g)
  { dim = Dim.MASS, factor = 1, label = "g", aliases = { "g", "gram", "grams", "克" } },
  { dim = Dim.MASS, factor = 1000, label = "kg", aliases = { "kg", "kilogram", "kilograms", "千克", "公斤" } },
  { dim = Dim.MASS, factor = 1e6, label = "t", aliases = { "t", "ton", "tons", "tonne", "tonnes", "吨" } },
  { dim = Dim.MASS, factor = 453.59237, label = "lb", aliases = { "lb", "lbs", "pound", "pounds", "磅" } },
  -- 中文质量单位仅用于美化输出（display_only，不参与输入解析）
  { dim = Dim.MASS, factor = 500, label = "斤", display_only = true },
  { dim = Dim.MASS, factor = 50, label = "两", display_only = true },
  { dim = Dim.MASS, factor = 5, label = "钱", display_only = true },
  { dim = Dim.MASS, factor = 50000, label = "担", display_only = true },
  -- time (base: s)
  { dim = Dim.TIME, factor = 1, label = "s", aliases = { "s", "sec", "secs", "second", "seconds", "秒" } },
  { dim = Dim.TIME, factor = 60, label = "min", aliases = { "min", "mins", "minute", "minutes", "分钟" } },
  { dim = Dim.TIME, factor = 3600, label = "h", aliases = { "h", "hr", "hrs", "hour", "hours", "小时" } },
  { dim = Dim.TIME, factor = 86400, label = "day", aliases = { "d", "day", "days", "天", "日" } },
  -- data (base: byte)；KB/MB/GB/TB 的进位可用 M.set_binary_bytes 切换
  { dim = Dim.DATA, factor = 0.125, label = "bit", aliases = { "bit", "bits" } },
  { dim = Dim.DATA, factor = 1, label = "B", aliases = { "b", "byte", "bytes" } },
  { dim = Dim.DATA, factor = BYTE_SCALE, label = "KB", aliases = { "kb" } },
  { dim = Dim.DATA, factor = BYTE_SCALE ^ 2, label = "MB", aliases = { "mb" } },
  { dim = Dim.DATA, factor = BYTE_SCALE ^ 3, label = "GB", aliases = { "gb" } },
  { dim = Dim.DATA, factor = BYTE_SCALE ^ 4, label = "TB", aliases = { "tb" } },
  { dim = Dim.DATA, factor = 1024, label = "KiB", aliases = { "kib" } },
  { dim = Dim.DATA, factor = 1024 ^ 2, label = "MiB", aliases = { "mib" } },
  { dim = Dim.DATA, factor = 1024 ^ 3, label = "GiB", aliases = { "gib" } },
  { dim = Dim.DATA, factor = 1024 ^ 4, label = "TiB", aliases = { "tib" } },
  -- speed (base: m/s)；km/h 之类的复合写法也可直接输入
  { dim = Dim.SPEED, factor = 1, label = "m/s", aliases = { "mps" } },
  { dim = Dim.SPEED, factor = 1000 / 3600, label = "km/h", aliases = { "kmh", "kph" } },
  { dim = Dim.SPEED, factor = 0.44704, label = "mph", aliases = { "mph" } },
  -- data rate (base: byte/s)；`MB/s` 走复合解析，mbps 等是独立别名
  { dim = Dim.DATA_RATE, factor = 125, label = "kbps", aliases = { "kbps" } },
  { dim = Dim.DATA_RATE, factor = 125000, label = "mbps", aliases = { "mbps" } },
  { dim = Dim.DATA_RATE, factor = 125000000, label = "gbps", aliases = { "gbps" } },
  -- power (base: W)
  { dim = Dim.POWER, factor = 1, label = "W", aliases = { "w", "watt", "watts" } },
  { dim = Dim.POWER, factor = 1000, label = "kW", aliases = { "kw" } },
}

for _, u in ipairs(M.UNITS) do
  if u.dim == Dim.DATA and (u.label == "KB" or u.label == "MB" or u.label == "GB" or u.label == "TB") then
    BYTE_UNITS[#BYTE_UNITS + 1] = u
  end
end

--- 切换十进制字节单位（KB/MB/GB/TB）的进位：false=1000（默认），true=1024。
function M.set_binary_bytes(enabled)
  BYTE_SCALE = enabled and 1024 or 1000
  for i, u in ipairs(BYTE_UNITS) do
    u.factor = BYTE_SCALE ^ i
  end
end

-- 相近单位的展示梯度：按 label 引用上面的单位定义，窗口滑动展示。
-- 输入解析只看英文缩写；这里允许混入中文等 display_only 单位。
M.LADDERS = {
  { dim = Dim.LENGTH, labels = { "km", "m", "cm", "mm" } },
  { dim = Dim.MASS, labels = { "t", "kg", "g", "斤", "两", "钱" } },
  { dim = Dim.TIME, labels = { "day", "h", "min", "s" } },
  { dim = Dim.DATA, labels = { "TB", "GB", "MB", "KB", "B" } },
  { dim = Dim.SPEED, labels = { "km/h", "m/s", "mph" } },
  { dim = Dim.DATA_RATE, labels = { "gbps", "mbps", "kbps" } },
  { dim = Dim.POWER, labels = { "kW", "W" } },
}

--- 找到某 dim 的展示梯度（ladder 为按 label 解析出的单位数组），没有则 nil。
function M.ladder_for(dim)
  for _, l in ipairs(M.LADDERS) do
    if Dim.eq(l.dim, dim) then
      local out = {}
      for _, label in ipairs(l.labels) do
        for _, u in ipairs(M.UNITS) do
          if u.label == label then
            out[#out + 1] = u
            break
          end
        end
      end
      return out
    end
  end
  return nil
end

-- alias (lowercase) -> currency code (uppercase)
M.CURRENCIES = {
  rmb = "CNY",
  cny = "CNY",
  yuan = "CNY",
  ["¥"] = "CNY",
  cn = "CNY",
  ["$"] = "USD",
  usd = "USD",
  dollar = "USD",
  dollars = "USD",
  us = "USD",
  ["€"] = "EUR",
  eur = "EUR",
  eu = "EUR",
  ["£"] = "GBP",
  gbp = "GBP",
  gb = "GBP",
  uk = "GBP",
  jpy = "JPY",
  yen = "JPY",
  jp = "JPY",
  hkd = "HKD",
  hk = "HKD",
  krw = "KRW",
  kr = "KRW",
  aud = "AUD",
  au = "AUD",
  cad = "CAD",
  ca = "CAD",
  chf = "CHF",
  ch = "CHF",
  sgd = "SGD",
  sg = "SGD",
}

local UNIT_INDEX = {}
for _, unit in ipairs(M.UNITS) do
  for _, alias in ipairs(unit.aliases or {}) do
    UNIT_INDEX[alias] = unit
  end
end

--- Look up a physical unit by alias. Input must already be lowercase.
function M.lookup_unit(name)
  return UNIT_INDEX[name]
end

--- 把汇率表中的货币代码注册为可用货币（如 thb -> THB）。
--- 固定的 CURRENCIES 表只提供别名/符号映射，具体支持哪些币种由 rates 决定。
--- Engine 加载汇率后调用。
function M.register_currency_codes(rates)
  for code in pairs(rates) do
    if type(code) == "string" and #code >= 2 then
      local lower = string.lower(code)
      if not M.CURRENCIES[lower] then
        M.CURRENCIES[lower] = string.upper(code)
      end
    end
  end
end

--- Look up a currency code by alias. Input must already be lowercase.
function M.lookup_currency(name)
  return M.CURRENCIES[name]
end

--- All known currency codes (uppercase), deduplicated.
function M.currency_codes()
  local seen, out = {}, {}
  for _, code in pairs(M.CURRENCIES) do
    if not seen[code] then
      seen[code] = true
      out[#out + 1] = code
    end
  end
  return out
end

--- Load an exchange-rate table from a JSON file path.
--- Returns (rates, nil) or (nil, err). Keys are uppercase codes;
--- values are units of `code` per 1 unit of the base currency (EUR).
function M.load_rates(path)
  local data, err = json.decode_file(path)
  if not data then
    return nil, "cannot read rates file `" .. tostring(path) .. "`: " .. tostring(err)
  end
  if type(data) ~= "table" or type(data.eur) ~= "table" then
    return nil, "rates file must contain the EUR base currency table"
  end
  local rates = {}
  for code, v in pairs(data.eur) do
    if type(v) == "number" then
      rates[string.upper(code)] = v
    end
  end
  return rates
end

--- Convert `v` units of `from` into `to` using `rates`:
--- `v / rate(from) * rate(to)`. Returns nil when a rate is missing.
function M.convert_currency(rates, v, from, to)
  local from_rate = rates[from]
  local to_rate = rates[to]
  if not from_rate or not to_rate or from_rate == 0 then
    return nil
  end
  return v / from_rate * to_rate
end

--- Pick a nice display unit for a base-dim value: prefer the unit giving
--- the smallest magnitude >= 1, falling back to the base unit.
function M.best_unit(dim, base_value)
  local best, best_v
  for _, unit in ipairs(M.UNITS) do
    if Dim.eq(unit.dim, dim) then
      local v = base_value / unit.factor
      if math.abs(v) >= 1 and (best == nil or math.abs(v) < math.abs(best_v)) then
        best, best_v = unit, v
      end
    end
  end
  if best then
    return best, best_v
  end
  for _, unit in ipairs(M.UNITS) do
    if Dim.eq(unit.dim, dim) then
      return unit, base_value / unit.factor
    end
  end
  return nil
end

return M
