local common = require("tests.common")
local test = require("lde-test")

local has_date = common.has_date
local civil = common.civil

-- Ambiguous inputs must yield multiple candidates instead of errors.

test.it("slash date plus days", function()
  -- `10/3 + 31d` reads as both Oct 3 and Mar 10 (fixed year 2026).
  local oct3 = civil.add_seconds(civil.datetime(2026, 10, 3, 0, 0, 0), 31 * 86400)
  local mar10 = civil.add_seconds(civil.datetime(2026, 3, 10, 0, 0, 0), 31 * 86400)
  has_date("10/3 + 31d", oct3.year, oct3.month, oct3.day)
  has_date("10/3 + 31d", mar10.year, mar10.month, mar10.day)
end)

test.it("invalid date falls back to error", function()
  -- 15/30 is not a valid date in either reading; fraction + duration is
  -- unsupported, so evaluation must fail gracefully (no panic).
  common.is_err("15/30 + 31d")
end)

test.it("bad input does not panic", function()
  local engine = common.engine()
  for _, input in ipairs({ "", "abc", "1 +", "to $", "1rmb rmb", "12:99 + 1h", "1/0" }) do
    engine:evaluate(input) -- may error, must not throw
  end
end)
