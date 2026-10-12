local common = require("tests.common")
local test = require("lde-test")

local civil = common.civil
local has_num = common.has_num
local has_time = common.has_time
local has_date = common.has_date
local has_datetime = common.has_datetime
local has_kind = common.has_kind

-- All cases run against FIXED_NOW (2026-10-04 12:00).

local function plus_days(dt, days)
  return civil.add_seconds(dt, days * 86400)
end

test.it("clock arithmetic", function()
  has_time("12:30 + 5h", 17, 30)
  has_time("12:30 - 1h", 11, 30)
  has_time("23:30 + 2h", 1, 30) -- wraps past midnight
  has_time("12:30 + 90min", 14, 0)
  -- implicit unit: bare number means hours for a clock
  has_time("12:30 + 5", 17, 30)
  -- 时长语境下 `m` 是分钟，不是米
  has_time("12:03 + 1d + 1m + 3s", 12, 4)
  has_time("12:03 + 3m + 3s", 12, 6)
end)

test.it("today plus days", function()
  local expected = plus_days(common.FIXED_NOW, 35)
  has_date("date + 35day", expected.year, expected.month, expected.day)
  has_date("today + 35d", expected.year, expected.month, expected.day)
end)

test.it("implicit days", function()
  local tomorrow = plus_days(common.FIXED_NOW, 1)
  has_date("date + 1", tomorrow.year, tomorrow.month, tomorrow.day)
end)

test.it("implicit days can be disabled", function()
  local engine = common.engine({ implicit_day = false })
  common.is_err("date + 1", engine)
end)

test.it("datetime plus hours evaluates", function()
  local cands = common.engine():evaluate("datetime + 5h")
  test.truthy(cands)
  test.greater(#cands, 0)
end)

test.it("temporal conversions", function()
  local today = common.FIXED_NOW
  -- time 显示为 datetime：用今天补全
  has_datetime("12:30 to datetime", today.year, today.month, today.day, 12, 30)
  has_kind("12:30 to date", "date")
  -- date 内部时间是当天 00:00
  has_time("date to time", 0, 0)
  has_datetime("date to datetime", today.year, today.month, today.day, 0, 0)
  -- datetime 可拆分
  has_date("datetime to date", today.year, today.month, today.day)
  -- temporal 目标作用于整个表达式（无需括号）
  local tomorrow = plus_days(today, 1)
  has_datetime("12:03 + 1d to datetime", tomorrow.year, tomorrow.month, tomorrow.day, 12, 3)
  has_datetime("(12:03 + 1d) to datetime", tomorrow.year, tomorrow.month, tomorrow.day, 12, 3)
  has_datetime("12:03 + 1d) to datetime", tomorrow.year, tomorrow.month, tomorrow.day, 12, 3)
  has_datetime("(12:03 + 1d + 1m + 3s) to datetime", tomorrow.year, tomorrow.month, tomorrow.day, 12, 4)
end)

test.it("dash date literals", function()
  -- 显式日期声明：无空格、分隔符一致的三段，年-月-日，两位年补 2000
  has_date("26-11-15", 2026, 11, 15)
  has_date("2026-11-15", 2026, 11, 15)
  has_date("25/11/01", 2025, 11, 1)
  local next_day = civil.add_seconds(civil.datetime(2026, 11, 15, 0, 0, 0), 86400)
  has_date("26-11-15 + 1d", next_day.year, next_day.month, next_day.day)
  has_date("date to date", 2026, 10, 4)
  -- 前导分隔符 + 两段（必须两位数字）= 当年的月-日
  has_date("-11-15", 2026, 11, 15)
  has_date("/11/15", 2026, 11, 15)
  has_date("-11-05", 2026, 11, 5)
  -- 位数不足两段回退为算术：`-5-3` = -5 - 3
  has_num("-5-3", -8)
  -- 前导 slash 位数不足不是日期（优雅报错）
  common.is_err("/5/3")
  -- 两段无空格分隔符仍是减法/除法
  has_num("5-3", 2)
  has_num("26-11", 15)
  has_num("11/15", 0.733333)
  -- 空格减法不受影响
  has_num("2026 - 11 - 15", 2000)
  -- 无效日期优雅报错
  common.is_err("26-13-01")
end)
