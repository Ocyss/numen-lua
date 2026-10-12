--- Shared helpers for value-level tests.
local civil = require("numen-core.civil")
local numen = require("numen-core")
local test = require("lde-test")

local M = {}

M.civil = civil
M.numen = numen

--- 固定的“当前时间”，避免测试随真实时间漂移。
M.FIXED_NOW = { year = 2026, month = 10, day = 4, hour = 12, min = 0, sec = 0 }

--- Build an engine with the fixed clock and the repo rates.json.
function M.engine(over)
  local cfg = { rates_path = os.getenv("NUMEN_RATES_PATH") or "rates.json", now = M.FIXED_NOW }
  if over then
    for k, v in pairs(over) do
      cfg[k] = v
    end
  end
  local engine, err = numen.Core.new(cfg)
  test.truthy(engine, err)
  return engine
end

function M.values(input, engine)
  engine = engine or M.engine()
  local cands, err = engine:evaluate(input)
  test.truthy(cands, "`" .. input .. "`: " .. tostring(err))
  local out = {}
  for _, c in ipairs(cands) do
    out[#out + 1] = c.value
  end
  return out
end

function M.round(v, dp)
  local mult = 10 ^ dp
  return math.floor(math.abs(v) * mult + 0.5) / mult * (v < 0 and -1 or 1)
end

function M.has_num(input, expected)
  for _, v in ipairs(M.values(input)) do
    if v.type == "num" and M.round(v.v, 6) == M.round(expected, 6) then
      return
    end
  end
  test.truthy(false, "`" .. input .. "`: expected num " .. tostring(expected))
end

--- currency compared at 2 decimal places (rates are not exact decimals)
function M.has_cur(input, code, expected)
  for _, v in ipairs(M.values(input)) do
    if v.type == "cur" and v.code == code and M.round(v.v, 2) == M.round(expected, 2) then
      return
    end
  end
  test.truthy(false, "`" .. input .. "`: expected " .. code .. " " .. tostring(expected))
end

--- quantity compared at 4 decimal places (compound factors involve division)
function M.has_qty(input, label, expected)
  for _, v in ipairs(M.values(input)) do
    if v.type == "qty" and v.label == label and M.round(v.v, 4) == M.round(expected, 4) then
      return
    end
  end
  test.truthy(false, "`" .. input .. "`: expected " .. label .. " " .. tostring(expected))
end

function M.has_time(input, h, m)
  for _, v in ipairs(M.values(input)) do
    if v.type == "temporal" and v.kind == "time" and v.dt.hour == h and v.dt.min == m then
      return
    end
  end
  test.truthy(false, string.format("`%s`: expected time %02d:%02d", input, h, m))
end

function M.has_date(input, y, m, d)
  for _, v in ipairs(M.values(input)) do
    if v.type == "temporal" and v.kind == "date" and civil.date_eq(v.dt, y, m, d) then
      return
    end
  end
  test.truthy(false, string.format("`%s`: expected date %04d-%02d-%02d", input, y, m, d))
end

function M.has_datetime(input, y, mo, d, h, mi)
  for _, v in ipairs(M.values(input)) do
    if
      v.type == "temporal"
      and v.kind == "datetime"
      and civil.date_eq(v.dt, y, mo, d)
      and v.dt.hour == h
      and v.dt.min == mi
    then
      return
    end
  end
  test.truthy(false, string.format("`%s`: expected datetime %04d-%02d-%02d %02d:%02d", input, y, mo, d, h, mi))
end

function M.has_kind(input, kind)
  for _, v in ipairs(M.values(input)) do
    if v.type == "temporal" and v.kind == kind then
      return
    end
  end
  test.truthy(false, "`" .. input .. "`: expected kind " .. kind)
end

function M.is_err(input, engine)
  engine = engine or M.engine()
  local cands = engine:evaluate(input)
  test.falsy(cands, "`" .. input .. "`: expected error")
end

return M
