local common = require("tests.common")
local test = require("lde-test")

local numen = common.numen
local has_qty = common.has_qty

--- 格式化所有候选为展示串
local function lines(input, engine, present_cfg)
  engine = engine or common.engine()
  local cands, err = engine:evaluate(input)
  test.truthy(cands, "`" .. input .. "`: " .. tostring(err))
  local presenter = numen.Present.new(present_cfg or {})
  return presenter:format_candidates(cands)
end

local function has_line(list, expected)
  for _, s in ipairs(list) do
    if s == expected then
      return
    end
  end
  test.truthy(false, "expected line `" .. expected .. "`, got: " .. table.concat(list, " | "))
end

test.it("data units", function()
  has_qty("1024 MB to GB", "GB", 1.024)
  has_qty("1 GiB to MiB", "MiB", 1024)
  has_qty("8 bit to B", "B", 1)
  has_qty("100 mbps", "mbps", 100)
  -- 复合写法 MB/s 与 mbps 同维度，可互相换算
  has_qty("100 mbps to MB/s", "MB/s", 12.5)
  has_qty("1 GB / 10 s", "mbps", 800)
end)

test.it("power units", function()
  has_qty("2 kW to W", "W", 2000)
  has_qty("1500 W + 500 W", "W", 2000)
end)

test.it("mass units with ton", function()
  has_qty("1 t to kg", "kg", 1000)
  has_qty("2 kg + 500 g", "kg", 2.5)
end)

test.it("binary bytes option", function()
  local engine = common.engine({ binary_bytes = true })
  local cands = engine:evaluate("1024 MB to GB")
  test.truthy(cands)
  test.equal(cands[1].value.v, 1)
  -- 默认 1000 进位
  local cands2 = common.engine({ binary_bytes = false }):evaluate("1000 MB to GB")
  test.equal(cands2[1].value.v, 1)
end)

test.it("nearby units", function()
  local l = lines("1 kg")
  has_line(l, "1 kg")
  has_line(l, "0.001 t")
  has_line(l, "1000 g")
  has_line(l, "2 斤")
  -- 显式换算不追加相近单位
  local l2 = lines("1 kg to g")
  has_line(l2, "1000 g")
  test.equal(#l2, 2) -- 结果 + 计算过程
end)

test.it("process candidate", function()
  local l = lines("$1 to rmb")
  -- 第一条是结果，第二条是过程
  test.truthy(l[1]:match("^¥"))
  test.truthy(l[2]:match("^%$1 to cny = "), "process line: " .. tostring(l[2]))
  local l3 = lines("1 kg to g")
  has_line(l3, "1 kg to g = 1000 g")
end)

test.it("rmb chinese amount", function()
  local l = lines("123.45 rmb")
  has_line(l, "¥123.45")
  has_line(l, "一百二十三元四角五分")
  has_line(l, "壹佰贰拾叁元肆角伍分")
  -- 整数金额带“整”
  has_line(lines("100 rmb"), "壹佰元整")
  -- 零几分
  has_line(lines("1.05 rmb"), "壹元零伍分")
  -- 非人民币不出中文金额
  local l4 = lines("1 usd", common.engine({ auto_convert_currency = false }))
  test.equal(#l4, 1)
end)

test.it("currencies extend from rates", function()
  -- 非固定别名表中的币种（如泰铢）只要 rates.json 里有就能用
  common.has_cur("100thb to rmb", "CNY", 20)
  common.has_cur("1cny to thb", "THB", 5)
end)
