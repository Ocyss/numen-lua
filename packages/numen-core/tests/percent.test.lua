local common = require("tests.common")
local test = require("lde-test")

local has_num = common.has_num
local has_cur = common.has_cur
local has_qty = common.has_qty

test.it("percent of", function()
  has_num("15% of 490", 73.5)
  has_cur("15% of 490$", "USD", 73.5)
  has_cur("10% of 10rmb", "CNY", 1)
end)

test.it("tip", function()
  has_cur("$55 + 25% tip", "USD", 68.75)
  has_cur("$55 + 25% TIP", "USD", 68.75)
end)

test.it("bare percent addsub is ambiguous", function()
  -- relative and literal candidates
  has_num("100 + 10%", 110)
  has_num("100 + 10%", 100.1)
  has_num("200 - 50%", 100)
  has_num("200 - 50%", 199.5)
  has_qty("100 kg + 10%", "kg", 110)
end)
