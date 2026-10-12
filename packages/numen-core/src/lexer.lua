--- Tokenizer. Tokens:
---   {kind="num", v=number}
---   {kind="ident", s=string}
---   {kind="symbol", c=string}        currency symbols: $ ¥ € £
---   {kind="clock", h=, m=}           HH:MM
---   {kind="datelit", y=, m=, d=}     26-11-15 / 2026-11-15 / -11-15 / 11/15
---   {kind="plus"|"minus"|"star"|"slash"|"percent"|"lparen"|"rparen"}

local M = {}

-- Split a UTF-8 string into an array of characters.
local function utf8_chars(s)
  local out = {}
  for c in s:gmatch(".[\128-\191]*") do
    out[#out + 1] = c
  end
  return out
end

local function is_digit(c)
  return #c == 1 and c:match("%d") ~= nil
end

local function is_space(c)
  return c:match("%s") ~= nil
end

-- Rust `is_alphabetic`: ASCII letters plus any non-ASCII (CJK, symbols we
-- handle separately are matched before this branch anyway).
local function is_alpha(c)
  return #c > 1 or c:match("[%a]") ~= nil
end

local SYMBOLS = { ["$"] = true, ["¥"] = true, ["€"] = true, ["£"] = true }

local function num(s)
  return tonumber(s)
end

function M.lex(input)
  local chars = utf8_chars(input)
  local n = #chars
  local out = {}
  local i = 1
  while i <= n do
    local c = chars[i]
    if is_space(c) then
      i = i + 1
    elseif c == "+" then
      out[#out + 1] = { kind = "plus" }
      i = i + 1
    elseif c == "-" or c == "/" then
      -- 前导分隔符 + 恰好两段同分隔符两位数字 → 当年的月-日：
      -- `-11-15`、`/11/15`。否则回退为普通运算符。
      local sep = c
      local j = i + 1
      while j <= n and is_digit(chars[j]) do
        j = j + 1
      end
      local groups = {}
      if j > i + 1 then
        groups[#groups + 1] = table.concat(chars, "", i + 1, j - 1)
        while j + 1 <= n and chars[j] == sep and is_digit(chars[j + 1]) do
          j = j + 1
          local gstart = j
          while j <= n and is_digit(chars[j]) do
            j = j + 1
          end
          groups[#groups + 1] = table.concat(chars, "", gstart, j - 1)
        end
      end
      if #groups == 2 and groups[1]:len() == 2 and groups[2]:len() == 2 then
        out[#out + 1] = { kind = "datelit", y = 0, m = num(groups[1]), d = num(groups[2]) }
        i = j
      else
        out[#out + 1] = { kind = sep == "-" and "minus" or "slash" }
        i = i + 1
      end
    elseif c == "*" or c == "×" then
      out[#out + 1] = { kind = "star" }
      i = i + 1
    elseif c == "%" then
      out[#out + 1] = { kind = "percent" }
      i = i + 1
    elseif c == "(" then
      out[#out + 1] = { kind = "lparen" }
      i = i + 1
    elseif c == ")" then
      out[#out + 1] = { kind = "rparen" }
      i = i + 1
    elseif SYMBOLS[c] then
      out[#out + 1] = { kind = "symbol", c = c }
      i = i + 1
    elseif is_digit(c) then
      local start = i
      while i <= n and is_digit(chars[i]) do
        i = i + 1
      end
      local int_part = table.concat(chars, "", start, i - 1)
      -- Clock literal: HH:MM
      if i + 1 <= n and chars[i] == ":" and is_digit(chars[i + 1]) then
        i = i + 1
        local mstart = i
        while i <= n and is_digit(chars[i]) do
          i = i + 1
        end
        local min_part = table.concat(chars, "", mstart, i - 1)
        out[#out + 1] = { kind = "clock", h = num(int_part), m = num(min_part) }
      else
        local s = int_part
        local has_fraction = false
        if i + 1 <= n and chars[i] == "." and is_digit(chars[i + 1]) then
          has_fraction = true
          s = s .. "."
          i = i + 1
          while i <= n and is_digit(chars[i]) do
            s = s .. chars[i]
            i = i + 1
          end
        end
        -- dash/slash 日期字面量：`26-11-15`、`25/11/01`
        -- （无空格、恰好三段、分隔符一致），否则回退为减法/除法。
        if not has_fraction and i + 1 <= n and (chars[i] == "-" or chars[i] == "/") and is_digit(chars[i + 1]) then
          local sep = chars[i]
          local groups = { int_part }
          while i + 1 <= n and chars[i] == sep and is_digit(chars[i + 1]) do
            i = i + 1
            local gstart = i
            while i <= n and is_digit(chars[i]) do
              i = i + 1
            end
            groups[#groups + 1] = table.concat(chars, "", gstart, i - 1)
          end
          if #groups == 3 then
            out[#out + 1] = {
              kind = "datelit",
              y = num(groups[1]),
              m = num(groups[2]),
              d = num(groups[3]),
            }
          else
            -- 回退为减法/除法：Num a, op, Num b, ...
            local op = sep == "-" and "minus" or "slash"
            out[#out + 1] = { kind = "num", v = num(groups[1]) }
            for k = 2, #groups do
              out[#out + 1] = { kind = op }
              out[#out + 1] = { kind = "num", v = num(groups[k]) }
            end
          end
        else
          out[#out + 1] = { kind = "num", v = num(s) }
        end
      end
    elseif is_alpha(c) then
      local start = i
      while i <= n and is_alpha(chars[i]) do
        i = i + 1
      end
      out[#out + 1] = { kind = "ident", s = string.lower(table.concat(chars, "", start, i - 1)) }
    else
      return nil, "unexpected character `" .. c .. "`"
    end
  end
  return out
end

return M
