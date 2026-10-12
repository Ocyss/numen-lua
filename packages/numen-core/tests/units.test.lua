local common = require("tests.common")
local test = require("lde-test")

local has_num = common.has_num
local has_qty = common.has_qty

test.it("dimension arithmetic", function()
  -- compound unit cancellation keeps the operand's unit
  has_qty("100 km/h * 2 h", "km", 200)
  has_qty("100 KM/H * 2 H", "km", 200)
  has_qty("10 kg * 3 + 500 g", "kg", 30.5)
  -- dimensionless results
  has_num("10 km / 5 km", 2)
end)

test.it("literals and aliases", function()
  has_qty("1千米", "km", 1)
  has_qty("1公里", "km", 1)
  has_qty("120码", "yd", 120)
  has_qty("500 g + 500 g", "g", 1000)
  has_qty("1 lb + 1 lb", "lb", 2)
end)

test.it("conversions", function()
  has_qty("1 mile to km", "km", 1.609344)
  has_qty("1kg in lb", "lb", 2.2046)
  has_qty("2 h to min", "min", 120)
end)

test.it("cross dimension add fails", function()
  common.is_err("1 kg + 1 km")
end)
