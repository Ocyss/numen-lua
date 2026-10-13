--- Evaluator: AST -> list of candidates.
--- A value is a tagged table:
---   {type="num", v=number}
---   {type="qty", v, dim, factor, label}
---   {type="cur", v, code}
---   {type="temporal", dt, kind}        kind: "date"|"time"|"datetime"
---   {type="str", s=string}             函数返回的文本结果（如 frexp）
--- A candidate is {value=..., note=string|nil}.

local civil = require("numen-core.civil")
local lexer = require("numen-core.lexer")
local parser = require("numen-core.parser")
local unit = require("numen-core.unit")

local Dim = unit.Dim

local unpack = unpack or table.unpack

local M = {}

local function single(value)
  return { { value = value } }
end

local function now(cfg)
  return cfg.now or civil.now()
end

local function fmt_value(v)
  if v.type == "num" then
    return "num(" .. tostring(v.v) .. ")"
  elseif v.type == "qty" then
    return "qty(" .. tostring(v.v) .. " " .. v.label .. ")"
  elseif v.type == "cur" then
    return "cur(" .. tostring(v.v) .. " " .. v.code .. ")"
  end
  return "temporal"
end

local eval -- forward declaration
local eval_funcall -- forward declaration

local function num_to_int(n, negate)
  local v = math.floor(math.abs(n)) * (n < 0 and -1 or 1)
  if negate then
    v = -v
  end
  return v
end

--- qty (TIME dim, or "m" interpreted as minutes) -> seconds
local function qty_to_span(qty, negate)
  if qty.type ~= "qty" then
    return nil, "expected a duration"
  end
  if not Dim.eq(qty.dim, Dim.TIME) then
    -- 时长语境下 `m` 按分钟解释
    if qty.label == "m" then
      return num_to_int(qty.v, negate) * 60
    end
    return nil, "expected a time duration"
  end
  local total = qty.v * qty.factor
  total = math.floor(math.abs(total)) * (total < 0 and -1 or 1)
  if negate then
    total = -total
  end
  return total
end

local function apply_span(v, secs)
  return { type = "temporal", dt = civil.add_seconds(v.dt, secs), kind = v.kind }
end

--- `a + n%` / `a - n%`: two candidate semantics (markup vs literal).
local function percent_addsub(n, op, lhs, cfg)
  local lcands, lerr = eval(lhs, cfg)
  if not lcands then
    return nil, lerr
  end
  local l = lcands[1].value
  local sign = op == "add" and 1 or -1
  local scale = 1 + sign * n / 100
  local out = {}
  if l.type == "num" then
    out[#out + 1] = { value = { type = "num", v = l.v * scale }, note = "relative" }
    out[#out + 1] = { value = { type = "num", v = l.v + sign * n / 100 }, note = "literal" }
  elseif l.type == "cur" then
    out[#out + 1] = { value = { type = "cur", v = l.v * scale, code = l.code }, note = "relative" }
  elseif l.type == "qty" then
    out[#out + 1] = {
      value = { type = "qty", v = l.v * scale, dim = l.dim, factor = l.factor, label = l.label },
      note = "relative",
    }
  else
    return nil, "cannot apply percentage to " .. fmt_value(l)
  end
  return out
end

--- `m/d + duration` interpreted as a date in the current year.
--- Yields both month/day and day/month readings when both are valid.
local function date_addsub_candidates(mv, dv, op, rhs, cfg)
  local rcands = eval(rhs, cfg)
  local r = rcands and rcands[1] and rcands[1].value
  if not r or r.type ~= "qty" or not Dim.eq(r.dim, Dim.TIME) then
    return {}
  end
  local span, err = qty_to_span(r, op == "sub")
  if not span then
    return nil, err
  end
  local year = now(cfg).year
  local a, b = num_to_int(mv, false), num_to_int(dv, false)
  local out = {}
  for _, md in ipairs({ { a, b }, { b, a } }) do
    local mm, dd = md[1], md[2]
    if civil.valid_date(year, mm, dd) then
      local dt = civil.add_seconds(civil.datetime(year, mm, dd, 0, 0, 0), span)
      local dup = false
      for _, c in ipairs(out) do
        if civil.dt_eq(c.value.dt, dt) then
          dup = true
          break
        end
      end
      if not dup then
        out[#out + 1] = {
          value = { type = "temporal", dt = dt, kind = "date" },
          note = "date",
        }
      end
    end
  end
  return out
end

local function eval_convert(inner, target, cfg)
  local cands, err = eval(inner, cfg)
  if not cands then
    return nil, err
  end
  local out = {}
  for _, c in ipairs(cands) do
    local v = c.value
    local value
    if v.type == "qty" and target.kind == "unit" then
      if not Dim.eq(v.dim, target.unit.dim) then
        return nil, "cannot convert between different dimensions"
      end
      value = {
        type = "qty",
        v = v.v * v.factor / target.unit.factor,
        dim = v.dim,
        factor = target.unit.factor,
        label = target.unit.label,
      }
    elseif v.type == "cur" and target.kind == "cur" then
      local converted = unit.convert_currency(cfg.rates, v.v, v.code, target.code)
      if not converted then
        return nil, "missing exchange rate"
      end
      value = { type = "cur", v = converted, code = target.code }
    elseif v.type == "temporal" and target.kind == "temporal" then
      -- 内部统一为完整 DateTime，互转仅改变显示粒度
      value = { type = "temporal", dt = v.dt, kind = target.tkind }
    else
      return nil, "cannot convert " .. fmt_value(v) .. " to " .. target.kind
    end
    -- exact: 显式换算结果不再追加相近单位候选；
    -- process: 供展示层生成「1 kg to g = 1000 g」这样的过程候选
    local process
    if target.kind == "unit" or target.kind == "cur" then
      process = { lhs = v, target = target }
    end
    out[#out + 1] = { value = value, note = c.note, exact = true, process = process }
  end
  return out
end

local function eval_bin(op, lhs, rhs, cfg)
  -- Percentage arithmetic: `a + n%` is ambiguous -> two candidates.
  if rhs.kind == "percent" and (op == "add" or op == "sub") then
    return percent_addsub(rhs.n, op, lhs, cfg)
  end
  -- `10/3 + 31d`: `a/b` next to a time quantity may be a month/day date.
  if op == "add" or op == "sub" then
    if lhs.kind == "bin" and lhs.op == "div" then
      local m, d = lhs.lhs, lhs.rhs
      if m.kind == "num" and d.kind == "num" then
        local cands, err = date_addsub_candidates(m.v, d.v, op, rhs, cfg)
        if cands and #cands > 0 then
          return cands
        end
        if cands == nil then
          return nil, err
        end
      end
    end
  end

  local lcands, lerr = eval(lhs, cfg)
  if not lcands then
    return nil, lerr
  end
  local rcands, rerr = eval(rhs, cfg)
  if not rcands then
    return nil, rerr
  end
  local l = lcands[1].value
  local r = rcands[1].value
  local err
  local value
  if op == "add" and l.type == "num" and r.type == "num" then
    value = { type = "num", v = l.v + r.v }
  elseif op == "sub" and l.type == "num" and r.type == "num" then
    value = { type = "num", v = l.v - r.v }
  elseif op == "mul" and l.type == "num" and r.type == "num" then
    value = { type = "num", v = l.v * r.v }
  elseif op == "div" and l.type == "num" and r.type == "num" then
    if r.v == 0 then
      return nil, "division by zero"
    end
    value = { type = "num", v = l.v / r.v }
  elseif op == "pow" and l.type == "num" and r.type == "num" then
    value = { type = "num", v = l.v ^ r.v }
  elseif (op == "add" or op == "sub") and l.type == "qty" and r.type == "qty" then
    if not Dim.eq(l.dim, r.dim) then
      return nil, "cannot add quantities of different dimensions"
    end
    local b_in_a = r.v * r.factor / l.factor
    local v = op == "add" and l.v + b_in_a or l.v - b_in_a
    value = { type = "qty", v = v, dim = l.dim, factor = l.factor, label = l.label }
  elseif (op == "add" or op == "sub") and l.type == "cur" and r.type == "cur" then
    local b_in_a = unit.convert_currency(cfg.rates, r.v, r.code, l.code)
    if not b_in_a then
      return nil, "missing exchange rate"
    end
    local v = op == "add" and l.v + b_in_a or l.v - b_in_a
    value = { type = "cur", v = v, code = l.code }
  elseif op == "mul" and l.type == "cur" and r.type == "num" then
    value = { type = "cur", v = l.v * r.v, code = l.code }
  elseif op == "mul" and l.type == "num" and r.type == "cur" then
    value = { type = "cur", v = r.v * l.v, code = r.code }
  elseif op == "div" and l.type == "cur" and r.type == "num" then
    if r.v == 0 then
      return nil, "division by zero"
    end
    value = { type = "cur", v = l.v / r.v, code = l.code }
  elseif op == "mul" and l.type == "qty" and r.type == "num" then
    value = { type = "qty", v = l.v * r.v, dim = l.dim, factor = l.factor, label = l.label }
  elseif op == "mul" and l.type == "num" and r.type == "qty" then
    value = { type = "qty", v = r.v * l.v, dim = r.dim, factor = r.factor, label = r.label }
  elseif op == "div" and l.type == "qty" and r.type == "num" then
    if r.v == 0 then
      return nil, "division by zero"
    end
    value = { type = "qty", v = l.v / r.v, dim = l.dim, factor = l.factor, label = l.label }
  elseif (op == "mul" or op == "div") and l.type == "qty" and r.type == "qty" then
    local base, dim
    if op == "mul" then
      base = l.v * l.factor * r.v * r.factor
      dim = Dim.mul(l.dim, r.dim)
    else
      if r.v * r.factor == 0 then
        return nil, "division by zero"
      end
      base = l.v * l.factor / (r.v * r.factor)
      dim = Dim.div(l.dim, r.dim)
    end
    if Dim.is_none(dim) then
      value = { type = "num", v = base }
    else
      -- Prefer the operand's own unit when it survives cancellation.
      local preferred
      for _, lbl in ipairs({ l.label, r.label }) do
        local numerator = lbl:match("^([^/]+)") or lbl
        for _, u in ipairs(unit.UNITS) do
          if Dim.eq(u.dim, dim) and u.label == numerator then
            preferred = u
            break
          end
        end
        if preferred then
          break
        end
      end
      local u, v
      if preferred then
        u, v = preferred, base / preferred.factor
      else
        u, v = unit.best_unit(dim, base)
        if not u then
          return nil, "no unit for resulting dimension"
        end
      end
      value = { type = "qty", v = v, dim = dim, factor = u.factor, label = u.label }
    end
  elseif (op == "add" or op == "sub") and l.type == "temporal" and r.type == "qty" then
    local span
    span, err = qty_to_span(r, op == "sub")
    if not span then
      return nil, err
    end
    value = apply_span(l, span)
  elseif (op == "add" or op == "sub") and l.type == "temporal" and r.type == "num" and cfg.implicit_day then
    -- implicit duration: `date + 1` means days, `12:30 + 1` means hours
    local n = num_to_int(r.v, op == "sub")
    local secs = l.kind == "time" and n * 3600 or n * 86400
    value = apply_span(l, secs)
  elseif op == "add" and l.type == "qty" and r.type == "temporal" then
    local span
    span, err = qty_to_span(l, false)
    if not span then
      return nil, err
    end
    value = apply_span(r, span)
  elseif op == "add" and l.type == "num" and r.type == "temporal" and cfg.implicit_day then
    local n = num_to_int(l.v, false)
    local secs = r.kind == "time" and n * 3600 or n * 86400
    value = apply_span(r, secs)
  elseif (op == "add" or op == "sub") and l.type == "qty" and r.type == "num" then
    -- bare number in the left operand's unit: `1d + 5` = 6 days
    local v = op == "add" and l.v + r.v or l.v - r.v
    value = { type = "qty", v = v, dim = l.dim, factor = l.factor, label = l.label }
  elseif (op == "add" or op == "sub") and l.type == "cur" and r.type == "num" then
    local v = op == "add" and l.v + r.v or l.v - r.v
    value = { type = "cur", v = v, code = l.code }
  else
    return nil, "unsupported operation " .. op
  end
  return single(value)
end

eval = function(expr, cfg)
  local k = expr.kind
  if k == "num" then
    return single({ type = "num", v = expr.v })
  elseif k == "const" then
    return single({ type = "num", v = expr.v })
  elseif k == "neg" then
    local cands, err = eval(expr.inner, cfg)
    if not cands then
      return nil, err
    end
    local v = cands[1].value
    if v.type ~= "num" then
      return nil, "cannot negate " .. fmt_value(v)
    end
    return single({ type = "num", v = -v.v })
  elseif k == "clock" then
    if not civil.valid_time(expr.h, expr.m, 0) then
      return nil, "hour/minute out of range"
    end
    local n = now(cfg)
    return single({
      type = "temporal",
      dt = civil.datetime(n.year, n.month, n.day, expr.h, expr.m, 0),
      kind = "time",
    })
  elseif k == "datelit" then
    -- y == 0: 前导分隔符写法（`-11-15`、`/11/15`），用当前年份
    local y = expr.y
    if y == 0 then
      y = now(cfg).year
    elseif y < 100 then
      y = 2000 + y
    end
    if not civil.valid_date(y, expr.m, expr.d) then
      return nil, "invalid date literal"
    end
    return single({
      type = "temporal",
      dt = civil.datetime(y, expr.m, expr.d, 0, 0, 0),
      kind = "date",
    })
  elseif k == "datetime" then
    local n = now(cfg)
    -- date 内部时间是当天 00:00（显示为 time/datetime 时自然是 0 点）
    local dt = expr.tkind == "date" and civil.datetime(n.year, n.month, n.day, 0, 0, 0) or n
    return single({ type = "temporal", dt = dt, kind = expr.tkind })
  elseif k == "qty" then
    return single({
      type = "qty",
      v = expr.v,
      dim = expr.unit.dim,
      factor = expr.unit.factor,
      label = expr.unit.label,
    })
  elseif k == "compound" then
    return single({
      type = "qty",
      v = expr.v,
      dim = expr.dim,
      factor = expr.factor,
      label = expr.label,
    })
  elseif k == "cur" then
    return single({ type = "cur", v = expr.v, code = expr.code })
  elseif k == "percent" then
    return single({ type = "num", v = expr.n / 100 })
  elseif k == "percentof" then
    local cands, err = eval(expr.inner, cfg)
    if not cands then
      return nil, err
    end
    local scale = expr.n / 100
    local out = {}
    for _, c in ipairs(cands) do
      local v = c.value
      local value
      if v.type == "num" then
        value = { type = "num", v = v.v * scale }
      elseif v.type == "qty" then
        value = { type = "qty", v = v.v * scale, dim = v.dim, factor = v.factor, label = v.label }
      elseif v.type == "cur" then
        value = { type = "cur", v = v.v * scale, code = v.code }
      else
        return nil, "cannot take percentage of " .. fmt_value(v)
      end
      out[#out + 1] = { value = value, note = c.note }
    end
    return out
  elseif k == "tipadd" then
    local cands, err = eval(expr.base, cfg)
    if not cands then
      return nil, err
    end
    local scale = 1 + expr.n / 100
    local out = {}
    for _, c in ipairs(cands) do
      local v = c.value
      local value
      if v.type == "num" then
        value = { type = "num", v = v.v * scale }
      elseif v.type == "cur" then
        value = { type = "cur", v = v.v * scale, code = v.code }
      elseif v.type == "qty" then
        value = { type = "qty", v = v.v * scale, dim = v.dim, factor = v.factor, label = v.label }
      else
        return nil, "cannot add tip to " .. fmt_value(v)
      end
      out[#out + 1] = { value = value, note = "with tip" }
    end
    return out
  elseif k == "convert" then
    return eval_convert(expr.inner, expr.target, cfg)
  elseif k == "bin" then
    return eval_bin(expr.op, expr.lhs, expr.rhs, cfg)
  elseif k == "funcall" then
    return eval_funcall(expr, cfg)
  end
  return nil, "unknown expression " .. tostring(k)
end

--- 数学函数表（参考 super_calculator.lua：https://github.com/ChaosAlphard ，贡献者 DeepChirp）
--- 每个函数接收数值参数，返回 number 或 string（string 以 str 类型候选展示）。
local funcs = {}

funcs.sin = math.sin
funcs.sinh = math.sinh
funcs.asin = math.asin
funcs.cos = math.cos
funcs.cosh = math.cosh
funcs.acos = math.acos
funcs.tan = math.tan
funcs.tanh = math.tanh
-- atan(x)：点相对于 x 轴的逆时针角度（弧度），x 为横纵坐标比值
funcs.atan = math.atan
-- atan2(y, x)：与 math.atan(y/x) 相比能正确处理边界情况（如 x = 0）
funcs.atan2 = math.atan2
  or function(y, x)
    return math.atan(y / x) + (x < 0 and (y >= 0 and math.pi or -math.pi) or 0)
  end
-- deg(π) = 180
funcs.deg = math.deg
-- rad(180) = π
funcs.rad = math.rad
funcs.exp = math.exp
funcs.sqrt = math.sqrt

-- log(y, x)：以 y 为底 x 的对数（换底公式）
function funcs.log(y, x)
  if x <= 0 or y <= 0 then
    return nil
  end
  return math.log(x) / math.log(y)
end

-- loge(x)：以 e 为底
function funcs.loge(x)
  if x <= 0 then
    return nil
  end
  return math.log(x)
end

-- log10(x)：以 10 为底
function funcs.log10(x)
  if x <= 0 then
    return nil
  end
  return math.log10(x)
end

-- 平均值
function funcs.avg(...)
  local n = select("#", ...)
  if n == 0 then
    return nil
  end
  local sum = 0
  for i = 1, n do
    sum = sum + select(i, ...)
  end
  return sum / n
end

-- 方差
function funcs.var(...)
  local n = select("#", ...)
  if n == 0 then
    return nil
  end
  local sum = 0
  for i = 1, n do
    sum = sum + select(i, ...)
  end
  local mean = sum / n
  local ssd = 0
  for i = 1, n do
    local v = select(i, ...)
    ssd = ssd + (v - mean) ^ 2
  end
  return ssd / n
end

-- 阶乘（非负整数）
function funcs.fact(x)
  if x < 0 or x ~= math.floor(x) then
    return nil
  end
  local result = 1
  for i = 2, x do
    result = result * i
  end
  return result
end

-- ldexp(x, y)：返回 x * 2^y
funcs.ldexp = math.ldexp or function(x, y)
  return x * 2 ^ y
end

-- frexp(x)：返回 "m * 2^e" 使得 x = m * 2^e（文本结果，不参与后续运算）
function funcs.frexp(x)
  if math.frexp then
    local m, e = math.frexp(x)
    return m .. " * 2^" .. e
  end
  if x == 0 then
    return "0 * 2^0"
  end
  local e = math.floor(math.log(math.abs(x)) / math.log(2)) + 1
  local m = x / 2 ^ e
  return m .. " * 2^" .. e
end

-- random([m [, n]])：m-n 之间的随机数；n 为空则 1-m；都为空则 0-1 之间的小数
local function random(...)
  return math.random(...)
end
funcs.rdm = random
funcs.random = random

--- 函数调用求值：参数先各自求值并取第一个候选，且必须为纯数值。
function eval_funcall(expr, cfg)
  local f = funcs[expr.name]
  if not f then
    return nil, "unknown function `" .. expr.name .. "`"
  end
  local args = {}
  for _, a in ipairs(expr.args) do
    local cands, err = eval(a, cfg)
    if not cands then
      return nil, err
    end
    local v = cands[1].value
    if v.type ~= "num" then
      return nil, "function `" .. expr.name .. "` expects numeric arguments, got " .. fmt_value(v)
    end
    args[#args + 1] = v.v
  end
  local result = f(unpack(args))
  if result == nil or result ~= result then
    return nil, "function `" .. expr.name .. "` returned no result (check argument range)"
  end
  if type(result) == "string" then
    return single({ type = "str", s = result })
  end
  return single({ type = "num", v = result })
end

M.eval = eval
M.funcs = funcs

--- 把 AST 重新格式化为规范表达式文本（`x` 归一为 `*`，括号按优先级补齐）。
--- 用于“补全后的表达式 = 结果”候选。
local BIN_OP_TEXT = { add = "+", sub = "-", mul = "*", div = "/", pow = "^" }
local BIN_OP_PREC = { add = 1, sub = 1, mul = 2, div = 2, pow = 3 }

local format_expr

local function fmt_ast_num(v)
  return string.format("%.14g", v)
end

-- 子表达式按优先级决定是否加括号；side: "left"|"right"（右操作数对非结合运算更严格）
local function fmt_child(e, parent_op, side)
  local s = format_expr(e)
  if e.kind == "bin" then
    local pp = BIN_OP_PREC[parent_op]
    local cp = BIN_OP_PREC[e.op]
    local need = cp < pp
    -- 右操作数：非结合运算（- / ^）同级也要加括号，如 a-(b-c)、a/(b/c)、a^(b^c)
    if
      not need
      and side == "right"
      and cp == pp
      and (parent_op == "sub" or parent_op == "div" or parent_op == "pow")
    then
      need = true
    end
    if need then
      return "(" .. s .. ")"
    end
  end
  return s
end

format_expr = function(e)
  local k = e.kind
  if k == "num" then
    return fmt_ast_num(e.v)
  elseif k == "const" then
    return e.name
  elseif k == "clock" then
    return string.format("%d:%02d", e.h, e.m)
  elseif k == "datelit" then
    if e.y == 0 then
      return "-" .. e.m .. "-" .. e.d
    end
    return e.y .. "-" .. e.m .. "-" .. e.d
  elseif k == "datetime" then
    return e.tkind
  elseif k == "qty" then
    return fmt_ast_num(e.v) .. " " .. e.unit.label
  elseif k == "compound" then
    return fmt_ast_num(e.v) .. " " .. e.label
  elseif k == "cur" then
    return fmt_ast_num(e.v) .. " " .. string.lower(e.code)
  elseif k == "percent" then
    return fmt_ast_num(e.n) .. "%"
  elseif k == "percentof" then
    return fmt_ast_num(e.n) .. "% of " .. format_expr(e.inner)
  elseif k == "tipadd" then
    return format_expr(e.base) .. " + " .. fmt_ast_num(e.n) .. "% tip"
  elseif k == "convert" then
    local target = e.target
    local t
    if target.kind == "unit" then
      t = target.unit.label
    elseif target.kind == "cur" then
      t = string.lower(target.code)
    else
      t = target.tkind
    end
    return format_expr(e.inner) .. " to " .. t
  elseif k == "bin" then
    return fmt_child(e.lhs, e.op, "left") .. BIN_OP_TEXT[e.op] .. fmt_child(e.rhs, e.op, "right")
  elseif k == "funcall" then
    local parts = {}
    for i, a in ipairs(e.args) do
      parts[i] = format_expr(a)
    end
    return e.name .. "(" .. table.concat(parts, ", ") .. ")"
  elseif k == "neg" then
    local s = format_expr(e.inner)
    if e.inner.kind == "bin" then
      s = "(" .. s .. ")"
    end
    return "-" .. s
  end
  return "?"
end

M.format_expr = format_expr

--- Engine: build once with a config, reuse for every input.
---
--- config fields:
---   base_currency: string (default "cny")
---   auto_convert_currency: boolean (default true)
---   implicit_day: boolean (default true)
---   now: civil datetime table | nil (fixed "current time", for tests)
---   rates_path: string | nil (path to rates.json)
---   rates: table | nil (pre-loaded rate table, takes precedence)
---   binary_bytes: boolean (default false) KB/MB/GB/TB 按 1024 进位
local Engine = {}
Engine.__index = Engine
M.Engine = Engine

function Engine.new(config)
  config = config or {}
  local cfg = {
    base_currency = config.base_currency or "cny",
    auto_convert_currency = config.auto_convert_currency ~= false,
    implicit_day = config.implicit_day ~= false,
    now = config.now,
  }
  unit.set_binary_bytes(config.binary_bytes == true)
  local rates = config.rates
  if not rates then
    local err
    rates, err = unit.load_rates(config.rates_path or "rates.json")
    if not rates then
      return nil, err
    end
  end
  cfg.rates = rates
  unit.register_currency_codes(rates)
  local base_code
  for _, code in ipairs(unit.currency_codes()) do
    if string.lower(code) == string.lower(cfg.base_currency) then
      base_code = code
      break
    end
  end
  if not base_code then
    return nil, "unknown base currency `" .. cfg.base_currency .. "`"
  end
  if rates[base_code] == nil then
    return nil, "no exchange rate for `" .. base_code .. "`"
  end
  cfg.base_code = base_code
  return setmetatable({ config = cfg }, Engine)
end

--- Evaluate an input expression into a list of candidates.
--- Returns (candidates, nil) or (nil, err).
function Engine:evaluate(input)
  local tokens, err = lexer.lex(input)
  if not tokens then
    return nil, err
  end
  -- 括号被自动补全时（如 `1+2)*5`），记录规范化后的表达式供展示
  local balanced = parser.balance_parens(tokens)
  local parens_fixed = #balanced ~= #tokens
  local expr
  expr, err = parser.parse(tokens)
  if not expr then
    return nil, err
  end
  local cands
  cands, err = eval(expr, self.config)
  if not cands then
    return nil, err
  end
  if parens_fixed then
    cands.expr = M.format_expr(expr)
  end
  if self.config.auto_convert_currency and expr.kind == "cur" then
    for _, c in ipairs(cands) do
      local v = c.value
      if v.type == "cur" and v.code ~= self.config.base_code then
        local converted = unit.convert_currency(self.config.rates, v.v, v.code, self.config.base_code)
        if converted then
          v.v = converted
          v.code = self.config.base_code
        end
      end
    end
  end
  return cands
end

return M
