--- 中文数字与人民币金额格式化（仅简体）。
--- 参考万象 super_calculator 的数字转换，裁剪为常用需求。

local M = {}

local LOWER_DIGITS = { "零", "一", "二", "三", "四", "五", "六", "七", "八", "九" }
local UPPER_DIGITS = { "零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖" }
local LOWER_PLACES = { "", "十", "百", "千" }
local UPPER_PLACES = { "", "拾", "佰", "仟" }
local GROUP_UNITS = { "", "万", "亿", "万亿" }

-- 4 位一组转换（group 为 1~4 位数字字符串，高位在前）
local function group_to_chinese(group, digits, places)
  local result = ""
  local pending_zero = false
  for i = 1, #group do
    local d = tonumber(group:sub(i, i))
    local place = #group - i + 1
    if d == 0 then
      if result ~= "" then
        pending_zero = true
      end
    else
      if pending_zero then
        result = result .. digits[1]
        pending_zero = false
      end
      result = result .. digits[d + 1] .. places[place]
    end
  end
  return result
end

--- 非负整数（数字字符串，<=16 位）转中文读数。
local function integer_to_chinese(int_str, upper)
  local digits = upper and UPPER_DIGITS or LOWER_DIGITS
  local places = upper and UPPER_PLACES or LOWER_PLACES
  int_str = int_str:gsub("^0+", "")
  if int_str == "" then
    return digits[1]
  end
  if #int_str > 16 then
    return nil
  end
  local groups = {}
  for finish = #int_str, 1, -4 do
    local start = math.max(1, finish - 3)
    groups[#groups + 1] = int_str:sub(start, finish)
  end
  local result = ""
  for i = #groups, 1, -1 do
    local gv = tonumber(groups[i])
    if gv == 0 then
      -- 整组为 0：若前后都有内容，补一个零（由下一非零组处理）
      if result ~= "" and i > 1 then
        -- 检查更低组是否有非零
        for j = i - 1, 1, -1 do
          if tonumber(groups[j]) ~= 0 then
            result = result .. digits[1]
            break
          end
        end
      end
    else
      if result ~= "" and gv < 1000 then
        -- 与上一组之间夹零，如 10001 -> 一万零一
        result = result .. digits[1]
      end
      result = result .. group_to_chinese(groups[i], digits, places) .. GROUP_UNITS[i]
    end
  end
  if not upper then
    result = result:gsub("^一十", "十")
  end
  return result
end

--- 金额（元）转中文：返回 小写/大写 金额字符串。
--- 超过分的小数按四舍五入到分。负数加“负”前缀。
--- upper: true 用壹贰叁，false 用一二三。
function M.money(v, upper)
  local neg = v < 0
  local cents = math.floor(math.abs(v) * 100 + 0.5)
  local yuan = math.floor(cents / 100)
  local jiao = math.floor((cents % 100) / 10)
  local fen = cents % 10
  local digits = upper and UPPER_DIGITS or LOWER_DIGITS

  local yuan_str = integer_to_chinese(tostring(yuan), upper)
  if not yuan_str then
    return nil
  end
  local result = yuan_str .. "元"
  if jiao == 0 and fen == 0 then
    result = result .. "整"
  else
    if jiao > 0 then
      result = result .. digits[jiao + 1] .. "角"
    elseif yuan > 0 and fen > 0 then
      result = result .. digits[1] -- 零几分
    end
    if fen > 0 then
      result = result .. digits[fen + 1] .. "分"
    end
  end
  if neg then
    result = "负" .. result
  end
  return result
end

--- 整数读数（不含单位“元”），供纯数字使用。
function M.integer(v, upper)
  if v ~= math.floor(v) or math.abs(v) >= 1e16 then
    return nil
  end
  local neg = v < 0
  local s = integer_to_chinese(tostring(math.abs(v)), upper)
  if not s then
    return nil
  end
  return neg and ("负" .. s) or s
end

return M
