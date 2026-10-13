local common = require("tests.common")
local test = require("lde-test")

local numen = common.numen

local function formatted(input)
  local engine = common.engine()
  local cands, err = engine:evaluate(input)
  test.truthy(cands, "`" .. input .. "`: " .. tostring(err))
  return numen.Present.new():format_candidates(cands)
end

test.it("basic formats", function()
  test.deepEqual(formatted("5rmb"), { "¥5", "五元整", "伍元整" })
  test.deepEqual(formatted("15% of 490"), { "73.5" })
  test.deepEqual(formatted("$55 + 25% tip"), { "$68.75 (with tip)" })
  test.deepEqual(formatted("12:30 + 5h"), { "17:30" })
  test.deepEqual(formatted("100 km/h * 2 h"), { "200 km", "200000 m" })
end)

test.it("paren completion shows normalized expression", function()
  test.deepEqual(formatted("1+2)*5"), { "15", "(1+2)*5 = 15" })
  test.deepEqual(formatted("1+2)x 5"), { "15", "(1+2)*5 = 15" })
  test.deepEqual(formatted("sin(pi/2"), { "1", "sin(pi/2) = 1" })
  -- 括号平衡时不追加
  test.deepEqual(formatted("(1+2)*5"), { "15" })
end)

test.it("seconds shown only when nonzero", function()
  test.deepEqual(formatted("12:03 + 3m"), { "12:06" })
  -- 秒非 00：H:M 与 H:M:S 两个变体都输出
  test.deepEqual(formatted("12:03 + 3m + 3s"), { "12:06", "12:06:03" })
end)

--- 固定时钟 2026-10-04 15:30:00 + 用户示例格式清单。
local function example_presenter()
  local engine = common.engine({
    now = { year = 2026, month = 10, day = 4, hour = 15, min = 30, sec = 0 },
  })
  local presenter = numen.Present.new({
    date_formats = {
      "Y年m月d日",
      "Y-m-d",
      "Y/m/d",
      "Y.m.d",
      "Ymd",
      "Y年n月j日",
      "y年n月j日",
      "n月j日",
    },
    time_formats = { "H:M", "H点M分", "H:M:S", "H时M分S秒", "下午I:M", "I:M P" },
    datetime_formats = { "Y-m-d H:M:S", "YmdHMS", "Y年m月d日 H点M分", "y/m/d I:M p" },
  })
  return engine, presenter
end

local function render(engine, presenter, input)
  local cands, err = engine:evaluate(input)
  test.truthy(cands, "`" .. input .. "`: " .. tostring(err))
  return presenter:format_candidates(cands)
end

test.it("date format variants", function()
  local engine, presenter = example_presenter()
  test.deepEqual(render(engine, presenter, "date"), {
    "2026年10月04日",
    "2026-10-04",
    "2026/10/04",
    "2026.10.04",
    "20261004",
    "2026年10月4日",
    "26年10月4日",
    "10月4日",
  })
end)

test.it("time format variants", function()
  local engine, presenter = example_presenter()
  -- 秒为 00：含 S 的格式被跳过
  test.deepEqual(render(engine, presenter, "15:30"), { "15:30", "15点30分", "下午3:30", "3:30 PM" })
end)

test.it("datetime format variants", function()
  local engine, presenter = example_presenter()
  -- 秒为 00：含 S 的格式被跳过
  test.deepEqual(render(engine, presenter, "datetime"), { "2026年10月04日 15点30分", "26/10/04 3:30 pm" })
  -- 秒非 00 时 S 格式启用
  test.deepEqual(render(engine, presenter, "datetime + 7s"), {
    "2026-10-04 15:30:07",
    "20261004153007",
    "2026年10月04日 15点30分",
    "26/10/04 3:30 pm",
  })
end)

test.it("ambiguous inputs list all candidates", function()
  test.deepEqual(formatted("100 + 10%"), { "110 (relative)", "100.1 (literal)" })
end)

test.it("money rounds to two decimals", function()
  -- default base currency is CNY
  test.deepEqual(formatted("1usd"), { "¥6.7", "六元七角", "陆元柒角" })
  -- configurable
  local engine = common.engine({ base_currency = "usd" })
  local cands = engine:evaluate("1rmb")
  test.truthy(cands)
  test.deepEqual(numen.Present.new():format_candidates(cands), { "$0.15" })
end)

test.it("normalize", function()
  test.equal(numen.normalize(" 12:06 "), "12:06")
  test.equal(numen.normalize("3:30 PM"), "3:30pm")
end)
