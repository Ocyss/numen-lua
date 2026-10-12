--- Candidate formatter: values/candidates -> display strings.
---
--- Time format pattern tokens:
---   Y 4-digit year, y 2-digit year, m/n month (padded/raw), d/j day (padded/raw),
---   H hour (24h padded), I hour (12h raw), M minute, S second,
---   P/p AM/PM (upper/lower), T literal T, O local timezone offset;
--- other characters pass through unchanged.
--- Formats containing `S` are skipped when seconds are 00.

local cnnum = require("numen-core.cnnum")
local unit = require("numen-core.unit")

local M = {}

local SYMBOLS = { CNY = "¥", USD = "$", EUR = "€", GBP = "£" }

local function currency_symbol(code)
  return SYMBOLS[code] or code
end

--- Round to `dp` decimals and render without trailing zeros.
local function fmt_rounded(v, dp)
  local mult = 10 ^ dp
  local r = math.floor(math.abs(v) * mult + 0.5) / mult
  if v < 0 then
    r = -r
  end
  local s = string.format("%." .. dp .. "f", r)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  if s == "-0" or s == "" then
    s = "0"
  end
  return s
end

local function fmt_decimal(v)
  -- integers render exactly; otherwise round to 6 decimal places
  if v == math.floor(v) and math.abs(v) < 1e15 then
    return string.format("%d", v)
  end
  return fmt_rounded(v, 6)
end

local function fmt_money(v)
  return fmt_rounded(v, 2)
end

local function pad2(n)
  return string.format("%02d", n)
end

local function render_temporal(dt, pattern)
  local out = {}
  local hour12 = dt.hour % 12
  if hour12 == 0 then
    hour12 = 12
  end
  local i = 1
  local len = #pattern
  while i <= len do
    -- pattern bytes may be UTF-8; tokens are ASCII so scan byte-wise
    local c = pattern:sub(i, i)
    if c == "Y" then
      out[#out + 1] = string.format("%04d", dt.year)
      i = i + 1
    elseif c == "y" then
      out[#out + 1] = pad2(dt.year % 100)
      i = i + 1
    elseif c == "m" then
      out[#out + 1] = pad2(dt.month)
      i = i + 1
    elseif c == "n" then
      out[#out + 1] = tostring(dt.month)
      i = i + 1
    elseif c == "d" then
      out[#out + 1] = pad2(dt.day)
      i = i + 1
    elseif c == "j" then
      out[#out + 1] = tostring(dt.day)
      i = i + 1
    elseif c == "H" then
      out[#out + 1] = pad2(dt.hour)
      i = i + 1
    elseif c == "I" then
      out[#out + 1] = tostring(hour12)
      i = i + 1
    elseif c == "M" then
      out[#out + 1] = pad2(dt.min)
      i = i + 1
    elseif c == "S" then
      out[#out + 1] = pad2(dt.sec)
      i = i + 1
    elseif c == "P" then
      out[#out + 1] = dt.hour < 12 and "AM" or "PM"
      i = i + 1
    elseif c == "p" then
      out[#out + 1] = dt.hour < 12 and "am" or "pm"
      i = i + 1
    elseif c == "T" then
      out[#out + 1] = "T"
      i = i + 1
    elseif c == "O" then
      -- local timezone offset, e.g. +08:00
      local ok, z = pcall(os.date, "%z")
      if ok and type(z) == "string" and #z == 5 then
        out[#out + 1] = z:sub(1, 3) .. ":" .. z:sub(4, 5)
      end
      i = i + 1
    else
      -- copy one UTF-8 char
      local b = pattern:byte(i)
      local size = 1
      if b >= 0xF0 then
        size = 4
      elseif b >= 0xE0 then
        size = 3
      elseif b >= 0xC0 then
        size = 2
      end
      out[#out + 1] = pattern:sub(i, i + size - 1)
      i = i + size
    end
  end
  return table.concat(out)
end

--- Presenter: build once with a FormatConfig, reuse for every input.
---
--- config fields (all optional):
---   date_formats: string[]     (default {"Y-m-d"})
---   time_formats: string[]     (default {"H:M", "H:M:S"})
---   datetime_formats: string[] (default {"Y-m-d H:M", "Y-m-d H:M:S"})
---   rmb_cn: boolean            (default true) 人民币结果附加中文金额候选
---   nearby_units: boolean      (default true) 数量结果附加相近单位候选
local Presenter = {}
Presenter.__index = Presenter
M.Presenter = Presenter

function Presenter.new(config)
  config = config or {}
  local cfg = {
    date_formats = config.date_formats or { "Y-m-d" },
    time_formats = config.time_formats or { "H:M", "H:M:S" },
    datetime_formats = config.datetime_formats or { "Y-m-d H:M", "Y-m-d H:M:S" },
    rmb_cn = config.rmb_cn ~= false,
    nearby_units = config.nearby_units ~= false,
  }
  return setmetatable({ config = cfg }, Presenter)
end

-- 相近单位的取值范围过滤：太小/太大的换算没有意义
local NEARBY_MIN, NEARBY_MAX = 1e-3, 1e6

--- 梯度上当前单位的位置：优先按 label 命中，否则按 factor 找第一个不大于它的位置。
local function ladder_index(ladder, factor, label)
  for i, u in ipairs(ladder) do
    if u.label == label then
      return i
    end
  end
  for i, u in ipairs(ladder) do
    if u.factor <= factor then
      return i
    end
  end
  return #ladder
end

--- 沿梯度滑动窗口（±2），产出当前单位之外、数值合理的相近单位展示串。
local function nearby_variants(value)
  local ladder = unit.ladder_for(value.dim)
  if not ladder then
    return {}
  end
  local idx = ladder_index(ladder, value.factor, value.label)
  local out = {}
  for i = math.max(1, idx - 2), math.min(#ladder, idx + 2) do
    local u = ladder[i]
    if u.label ~= value.label then
      local v = value.v * value.factor / u.factor
      if math.abs(v) >= NEARBY_MIN and math.abs(v) <= NEARBY_MAX then
        out[#out + 1] = fmt_decimal(v) .. " " .. u.label
      end
    end
  end
  return out
end

--- Format a single value into all configured display variants
--- (deduplicated, order preserved).
--- opts.nearby: 是否附加相近单位（显式换算结果不需要）
function Presenter:format_value(value, opts)
  opts = opts or {}
  if value.type == "num" then
    return { fmt_decimal(value.v) }
  end
  if value.type == "qty" then
    local out = { fmt_decimal(value.v) .. " " .. value.label }
    if self.config.nearby_units and opts.nearby then
      for _, s in ipairs(nearby_variants(value)) do
        out[#out + 1] = s
      end
    end
    return out
  end
  if value.type == "cur" then
    local out = { currency_symbol(value.code) .. fmt_money(value.v) }
    if self.config.rmb_cn and value.code == "CNY" then
      local lower = cnnum.money(value.v, false)
      local upper = cnnum.money(value.v, true)
      if lower then
        out[#out + 1] = lower
      end
      if upper and upper ~= lower then
        out[#out + 1] = upper
      end
    end
    return out
  end
  -- temporal
  local patterns
  if value.kind == "date" then
    patterns = self.config.date_formats
  elseif value.kind == "time" then
    patterns = self.config.time_formats
  else
    patterns = self.config.datetime_formats
  end
  local out = {}
  for _, p in ipairs(patterns) do
    -- 秒为 00 时，含 `S` 的格式会被跳过
    if not (value.dt.sec == 0 and p:find("S", 1, true)) then
      local s = render_temporal(value.dt, p)
      local dup = false
      for _, existing in ipairs(out) do
        if existing == s then
          dup = true
          break
        end
      end
      if not dup then
        out[#out + 1] = s
      end
    end
  end
  return out
end

--- 换算目标的展示名：`to kg` / `to rmb`
local function target_desc(target)
  if target.kind == "unit" then
    return target.unit.label
  end
  if target.kind == "cur" then
    return string.lower(target.code)
  end
  return target.tkind or ""
end

--- Format all candidates for display (deduplicated, order preserved).
function Presenter:format_candidates(candidates)
  local out = {}
  local function push(s)
    for _, existing in ipairs(out) do
      if existing == s then
        return
      end
    end
    out[#out + 1] = s
  end
  for _, c in ipairs(candidates) do
    local strings = self:format_value(c.value, { nearby = not c.exact })
    for i, s in ipairs(strings) do
      if c.note then
        s = s .. " (" .. c.note .. ")"
      end
      push(s)
      -- 固定追加一条计算过程候选：`$1 to cny = ¥7.10`
      if i == 1 and c.process then
        local lhs = self:format_value(c.process.lhs, {})[1]
        push(lhs .. " to " .. target_desc(c.process.target) .. " = " .. s)
      end
    end
  end
  return out
end

--- Normalize a display string for comparison: lowercase, no whitespace.
function M.normalize(s)
  return (s:gsub("%s", "")):lower()
end

return M
