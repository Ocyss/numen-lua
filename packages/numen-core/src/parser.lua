--- Recursive-descent parser producing an AST:
---   {kind="num", v}
---   {kind="clock", h, m}
---   {kind="datelit", y, m, d}
---   {kind="datetime", tkind}           tkind: "date"|"time"|"datetime"
---   {kind="qty", v, unit}
---   {kind="compound", v, dim, factor, label}
---   {kind="cur", v, code}
---   {kind="percent", n}
---   {kind="percentof", n, inner}
---   {kind="tipadd", base, n}
---   {kind="convert", inner, target}    target: {kind="unit"|"cur"|"temporal", ...}
---   {kind="bin", op, lhs, rhs}         op: "add"|"sub"|"mul"|"div"

local unit = require("numen-core.unit")

local M = {}

local lookup_unit = unit.lookup_unit
local lookup_currency = unit.lookup_currency
local Dim = unit.Dim

--- Tolerate unbalanced parentheses (the user is still typing):
--- drop unmatched `)`, append missing `)` at the end.
local function balance_parens(tokens)
  local depth = 0
  local out = {}
  for _, t in ipairs(tokens) do
    if t.kind == "lparen" then
      depth = depth + 1
      out[#out + 1] = t
    elseif t.kind == "rparen" and depth == 0 then
      -- stray `)`: drop it
    elseif t.kind == "rparen" then
      depth = depth - 1
      out[#out + 1] = t
    else
      out[#out + 1] = t
    end
  end
  for _ = 1, depth do
    out[#out + 1] = { kind = "rparen" }
  end
  return out
end

local function fmt_tok(t)
  if t == nil then
    return "<eof>"
  end
  return t.kind
end

local Parser = {}
Parser.__index = Parser

function Parser:peek()
  return self.toks[self.pos]
end

function Parser:peek_at(offset)
  return self.toks[self.pos + offset]
end

function Parser:next()
  local t = self.toks[self.pos]
  if t then
    self.pos = self.pos + 1
  end
  return t
end

function Parser:eat_kw(kw)
  local t = self:peek()
  if t and t.kind == "ident" and t.s == kw then
    self.pos = self.pos + 1
    return true
  end
  return false
end

function Parser:parse_target()
  local t = self:next()
  if t == nil then
    return nil, "expected unit or currency, got <eof>"
  end
  if t.kind == "symbol" then
    local code = lookup_currency(t.c)
    if code then
      return { kind = "cur", code = code }
    end
    return nil, "unknown currency symbol `" .. t.c .. "`"
  end
  if t.kind == "ident" then
    local name = t.s
    -- 单位优先于货币：`to gb` 指 GB 而非英镑（英镑用 gbp）
    local u = lookup_unit(name)
    if u then
      -- 复合目标单位：`to MB/s`、`to km/h`
      local dim, factor, label = u.dim, u.factor, u.label
      while true do
        local slash = self:peek()
        local nx = self:peek_at(1)
        if not (slash and slash.kind == "slash" and nx and nx.kind == "ident" and lookup_unit(nx.s)) then
          break
        end
        self.pos = self.pos + 2
        local u2 = lookup_unit(nx.s)
        dim = Dim.div(dim, u2.dim)
        factor = factor / u2.factor
        label = label .. "/" .. u2.label
      end
      return { kind = "unit", unit = { dim = dim, factor = factor, label = label } }
    end
    local code = lookup_currency(name)
    if code then
      return { kind = "cur", code = code }
    end
    if name == "date" or name == "time" or name == "datetime" then
      return { kind = "temporal", tkind = name }
    end
    return nil, "unknown conversion target `" .. name .. "`"
  end
  return nil, "expected unit or currency, got " .. fmt_tok(t)
end

--- convert := postfix (("to" | "in") target)*
--- conversion binds tighter than `*`/`/`/`+`/`-`.
--- Temporal targets are left for the top level.
function Parser:parse_convert()
  local e, err = self:parse_postfix()
  if not e then
    return nil, err
  end
  while true do
    local t = self:peek()
    local is_convert = t and t.kind == "ident" and (t.s == "to" or t.s == "in")
    if not is_convert then
      break
    end
    local nx = self:peek_at(1)
    local temporal_target = nx and nx.kind == "ident" and (nx.s == "date" or nx.s == "time" or nx.s == "datetime")
    if temporal_target then
      break
    end
    self.pos = self.pos + 1
    local target
    target, err = self:parse_target()
    if not target then
      return nil, err
    end
    e = { kind = "convert", inner = e, target = target }
  end
  return e
end

--- add := mul (("+" | "-") mul "tip"?)*
function Parser:parse_add()
  local e, err = self:parse_mul()
  if not e then
    return nil, err
  end
  while true do
    local t = self:peek()
    local op
    if t and t.kind == "plus" then
      op = "add"
    elseif t and t.kind == "minus" then
      op = "sub"
    else
      break
    end
    self.pos = self.pos + 1
    local rhs
    rhs, err = self:parse_mul()
    if not rhs then
      return nil, err
    end
    -- `x + n% tip` sugar
    if rhs.kind == "percent" and op == "add" and self:eat_kw("tip") then
      e = { kind = "tipadd", base = e, n = rhs.n }
    else
      e = { kind = "bin", op = op, lhs = e, rhs = rhs }
    end
  end
  return e
end

--- mul := convert (("of" | "*" | "x" | "/") convert)*
function Parser:parse_mul()
  local e, err = self:parse_convert()
  if not e then
    return nil, err
  end
  while true do
    local t = self:peek()
    if t and t.kind == "ident" and t.s == "of" then
      self.pos = self.pos + 1
      if e.kind ~= "percent" then
        return nil, "`of` requires a percentage on the left"
      end
      local rhs
      rhs, err = self:parse_convert()
      if not rhs then
        return nil, err
      end
      e = { kind = "percentof", n = e.n, inner = rhs }
    elseif t and t.kind == "star" then
      self.pos = self.pos + 1
      local rhs
      rhs, err = self:parse_convert()
      if not rhs then
        return nil, err
      end
      e = { kind = "bin", op = "mul", lhs = e, rhs = rhs }
    elseif t and t.kind == "ident" and t.s == "x" then
      -- `x` as a multiplication sign: `5d x 120km/h`
      self.pos = self.pos + 1
      local rhs
      rhs, err = self:parse_convert()
      if not rhs then
        return nil, err
      end
      e = { kind = "bin", op = "mul", lhs = e, rhs = rhs }
    elseif t and t.kind == "slash" then
      self.pos = self.pos + 1
      local rhs
      rhs, err = self:parse_convert()
      if not rhs then
        return nil, err
      end
      e = { kind = "bin", op = "div", lhs = e, rhs = rhs }
    else
      break
    end
  end
  return e
end

--- postfix := primary (unit | currency | "/" unit)*
function Parser:parse_postfix()
  local e, err = self:parse_primary()
  if not e then
    return nil, err
  end
  while true do
    local t = self:peek()
    if t and t.kind == "ident" then
      local applied = false
      if e.kind == "num" then
        -- 单位优先于货币：`1 GB` 指吉字节而非英镑（英镑用 gbp）
        local u = lookup_unit(t.s)
        if u then
          self.pos = self.pos + 1
          e = { kind = "qty", v = e.v, unit = u }
          applied = true
        else
          local code = lookup_currency(t.s)
          if code then
            self.pos = self.pos + 1
            e = { kind = "cur", v = e.v, code = code }
            applied = true
          end
        end
      end
      if not applied then
        break
      end
    elseif t and t.kind == "symbol" then
      if e.kind == "num" then
        local code = lookup_currency(t.c)
        if not code then
          return nil, "unknown currency symbol `" .. t.c .. "`"
        end
        self.pos = self.pos + 1
        e = { kind = "cur", v = e.v, code = code }
      else
        break
      end
    elseif t and t.kind == "percent" then
      if e.kind == "num" then
        self.pos = self.pos + 1
        e = { kind = "percent", n = e.v }
      else
        break
      end
    elseif t and t.kind == "slash" then
      -- compound unit: quantity / unit, e.g. `100 km/h`
      local nx = self:peek_at(1)
      local is_compound = nx and nx.kind == "ident" and lookup_unit(nx.s) ~= nil
      local is_qty = e.kind == "qty" or e.kind == "compound"
      if not (is_compound and is_qty) then
        break
      end
      self.pos = self.pos + 1 -- '/'
      local name = self:next().s
      local u = lookup_unit(name)
      if e.kind == "qty" then
        e = {
          kind = "compound",
          v = e.v,
          dim = Dim.div(e.unit.dim, u.dim),
          factor = e.unit.factor / u.factor,
          label = e.unit.label .. "/" .. u.label,
        }
      else
        e = {
          kind = "compound",
          v = e.v,
          dim = Dim.div(e.dim, u.dim),
          factor = e.factor / u.factor,
          label = e.label .. "/" .. u.label,
        }
      end
    else
      break
    end
  end
  return e
end

--- primary := number | clock | symbol number | currency number | unit number
---          | "date" | "datetime" | "-" primary | "(" add ")"
function Parser:parse_primary()
  local t = self:peek()
  if t == nil then
    return nil, "unexpected token <eof>"
  end
  if t.kind == "lparen" then
    self.pos = self.pos + 1
    local e, err = self:parse_add()
    if not e then
      return nil, err
    end
    local c = self:peek()
    if c and c.kind == "rparen" then
      self.pos = self.pos + 1
    else
      return nil, "expected `)`, got " .. fmt_tok(c)
    end
    return e
  end
  if t.kind == "num" then
    self.pos = self.pos + 1
    return { kind = "num", v = t.v }
  end
  if t.kind == "clock" then
    self.pos = self.pos + 1
    return { kind = "clock", h = t.h, m = t.m }
  end
  if t.kind == "datelit" then
    self.pos = self.pos + 1
    return { kind = "datelit", y = t.y, m = t.m, d = t.d }
  end
  if t.kind == "minus" then
    self.pos = self.pos + 1
    local e, err = self:parse_primary()
    if not e then
      return nil, err
    end
    if e.kind == "num" then
      return { kind = "num", v = -e.v }
    end
    return nil, "cannot negate " .. e.kind
  end
  if t.kind == "symbol" then
    self.pos = self.pos + 1
    local code = lookup_currency(t.c)
    if not code then
      return nil, "unknown currency symbol `" .. t.c .. "`"
    end
    local nx = self:next()
    if nx and nx.kind == "num" then
      return { kind = "cur", v = nx.v, code = code }
    end
    return nil, "expected number after `" .. t.c .. "`, got " .. fmt_tok(nx)
  end
  if t.kind == "ident" then
    local name = t.s
    if name == "date" or name == "today" then
      self.pos = self.pos + 1
      return { kind = "datetime", tkind = "date" }
    end
    if name == "time" then
      self.pos = self.pos + 1
      return { kind = "datetime", tkind = "time" }
    end
    if name == "datetime" or name == "now" then
      self.pos = self.pos + 1
      return { kind = "datetime", tkind = "datetime" }
    end
    -- prefix unit/currency: `rmb 10`, `km 5`
    local u0 = lookup_unit(name)
    if u0 then
      self.pos = self.pos + 1
      local nx = self:next()
      if nx and nx.kind == "num" then
        return { kind = "qty", v = nx.v, unit = u0 }
      end
      return nil, "expected number after `" .. name .. "`, got " .. fmt_tok(nx)
    end
    local code = lookup_currency(name)
    if code then
      self.pos = self.pos + 1
      local nx = self:next()
      if nx and nx.kind == "num" then
        return { kind = "cur", v = nx.v, code = code }
      end
      return nil, "expected number after `" .. name .. "`, got " .. fmt_tok(nx)
    end
    return nil, "unknown word `" .. name .. "`"
  end
  return nil, "unexpected token " .. fmt_tok(t)
end

function M.parse(tokens)
  if #tokens == 0 then
    return nil, "empty input"
  end
  tokens = balance_parens(tokens)
  local p = setmetatable({ toks = tokens, pos = 1 }, Parser)
  local e, err = p:parse_add()
  if not e then
    return nil, err
  end
  -- 顶层换算作用于整个表达式（如 `12:03 + 1d to datetime`）。
  while p:eat_kw("to") or p:eat_kw("in") do
    local target
    target, err = p:parse_target()
    if not target then
      return nil, err
    end
    e = { kind = "convert", inner = e, target = target }
  end
  if p.pos <= #tokens then
    return nil, "unexpected trailing token " .. fmt_tok(tokens[p.pos])
  end
  return e
end

return M
