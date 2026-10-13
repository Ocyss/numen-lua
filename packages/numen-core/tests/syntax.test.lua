local common = require("tests.common")
local test = require("lde-test")

local has_num = common.has_num
local has_cur = common.has_cur
local has_qty = common.has_qty
local has_date = common.has_date

test.it("parentheses grouping", function()
  has_qty("(10 kg * 3) + 500 g", "kg", 30.5)
  has_num("(1 + 2) * 3", 9)
  has_qty("(2 h) * 100 km/h", "km", 200)
  has_qty("(5d to h) x 120 km/h", "km", 14400)
end)

test.it("conversion binds tighter than multiply", function()
  -- `to`/`in` 优先级高于乘除：等价于 `(5d to h) * 120km/h`
  has_qty("5d to h x 120km/h", "km", 14400)
  has_qty("5d to h * 120 km/h", "km", 14400)
end)

test.it("x multiplies", function()
  has_num("3 x 4", 12)
  has_qty("2h x 60 km/h", "km", 120)
end)

test.it("unclosed paren is auto completed", function()
  -- user is still typing: `(1 + 2` behaves like `(1 + 2)`
  has_num("(1 + 2", 3)
  has_num("((1 + 2) * 3", 9)
end)

test.it("stray close paren wraps the preceding expression", function()
  -- `1 + 2) * 3` behaves like `(1 + 2) * 3`
  has_num("1 + 2) * 3", 9)
  has_num("1 + 2 * 5)x2", 22)
  has_num("1 + 2 * 5)x2+1", 23)
  has_num("(1 + 2 * 5)x2+1)*2", 46)
  has_num("1 + 2 * 5)x2+1)*2", 46)
  has_qty("5d to h) x 120km/h", "km", 14400)
end)

test.it("date arithmetic is symmetric", function()
  local expected = common.civil.add_seconds(common.FIXED_NOW, 5 * 86400)
  has_date("5 + date", expected.year, expected.month, expected.day)
  has_date("5d + date", expected.year, expected.month, expected.day)
end)

test.it("bare number uses left unit", function()
  has_qty("1d + 5", "day", 6)
  has_qty("1km + 500", "km", 501)
  has_cur("$5 + 5", "USD", 10)
end)
