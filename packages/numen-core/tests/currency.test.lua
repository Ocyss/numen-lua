local common = require("tests.common")
local test = require("lde-test")

local has_cur = common.has_cur

-- Rates come from rates.json (fawazahmed0/currency-api format, base EUR).

test.it("explicit conversions", function()
  has_cur("1rmb to $", "USD", 0.15)
  has_cur("1¥ to $", "USD", 0.15)
  has_cur("¥1 in $", "USD", 0.15)
  has_cur("rmb 10 to $", "USD", 1.49)
  has_cur("$1 to rmb", "CNY", 6.70)
  has_cur("1usd to eur", "EUR", 0.89)
  has_cur("100 usd in gbp", "GBP", 75.53)
end)

test.it("case insensitive", function()
  has_cur("1RMB TO $", "USD", 0.15)
  has_cur("Rmb 10 To $", "USD", 1.49)
end)

test.it("bare currency uses base currency", function()
  -- default config: base = CNY
  has_cur("5rmb", "CNY", 5)
  has_cur("1usd", "CNY", 6.70)
  has_cur("1jp", "CNY", 0.04)
  has_cur("1us", "CNY", 6.70)
end)

test.it("base currency is configurable", function()
  local engine = common.engine({ base_currency = "usd" })
  local cands = engine:evaluate("1rmb")
  test.truthy(cands)
  local found = false
  for _, c in ipairs(cands) do
    if c.value.type == "cur" and c.value.code == "USD" and common.round(c.value.v, 2) == 0.15 then
      found = true
    end
  end
  test.truthy(found)
end)

test.it("same currency arithmetic", function()
  has_cur("$55 + $5", "USD", 60)
  has_cur("$55 - $5", "USD", 50)
  has_cur("10rmb * 2", "CNY", 20)
  has_cur("10rmb / 10", "CNY", 1)
  has_cur("10rmb * 10%", "CNY", 1)
end)
