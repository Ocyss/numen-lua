package.path = package.path .. ";./target/?.lua;./target/?/init.lua"
package.cpath = package.cpath .. ";./target/?.so" .. ";./target/?.dll" .. ";./target/?.dylib"

local eval = require("numen-core.eval")
local present = require("numen-core.present")

local M = {}

--- The evaluation engine. Create with its own config:
---
---   local core = numen.Core.new({
---       base_currency = "cny",          -- default
---       auto_convert_currency = true,   -- default
---       implicit_day = true,            -- default
---       now = {year=2026, month=10, day=4, hour=12, min=0, sec=0}, -- fixed clock (tests)
---       rates_path = "rates.json",      -- path to exchange-rate JSON
---   })
---   local cands, err = core:evaluate("1usd to rmb")
M.Core = eval.Engine

--- The candidate formatter. Create with its own config:
---
---   local present = numen.Present.new({
---       date_formats = { "Y-m-d" },
---       time_formats = { "H:M", "H:M:S" },
---       datetime_formats = { "Y-m-d H:M", "Y-m-d H:M:S" },
---   })
---   local lines = present:format_candidates(cands)
M.Present = present.Presenter

M.normalize = present.normalize

return M
