-- numen Rime translator
--
-- 参考 super_calculator.lua 的 Rime 适配方式，将求值逻辑交给 numen 引擎。
-- 在 rime 方案中配置:
--   recognizer/patterns/numen: "^V.*"   # 触发前缀
--   translators: [lua_translator@numen]
--   processors: [lua_processor@numen]    # 可选：V 模式下空格不上屏
--   numen:
--     tips: "计算"                     # 提示文字
--     rates_path: "rates.json"         # 汇率文件路径（默认取脚本旁的 rates.json）
--     base_currency: "cny"             # 基准货币
--     auto_convert_currency: true      # 自动换算为基准货币
--     implicit_day: true               # 时间表达式缺省补当天
--     date_formats: ["Y-m-d", "Y年m月d日"]  # 日期输出格式
--     time_formats: ["H:M", "H:M:S"]   # 时间输出格式
--     datetime_formats: ["Y-m-d H:M"]  # 日期时间输出格式
--     binary_bytes: true               # KB/MB/GB/TB 按 1024 进位（默认 1000）
--     rmb_cn: true                     # 人民币结果附加中文金额候选（默认开）
--     nearby_units: true               # 数量结果附加相近单位候选（默认开）

local ok, numen = pcall(require, "numen-core")

-- 依次尝试：原路径 > rime 用户目录下的同名相对路径 > rime 系统目录下的同名相对路径
-- （与万象 wanxiang.load_file_with_fallback 一致）
local function resolve_rates_path(path)
  if not path then
    return nil
  end
  local function readable(p)
    local f = p and io.open(p, "rb")
    if f then
      f:close()
      return true
    end
    return false
  end
  if readable(path) then
    return path
  end
  local rel = path:gsub("^[\\/]+", "")
  if rime_api and rime_api.get_user_data_dir then
    local candidate = rime_api.get_user_data_dir() .. "/" .. rel
    if readable(candidate) then
      return candidate
    end
  end
  if rime_api and rime_api.get_shared_data_dir then
    local candidate = rime_api.get_shared_data_dir() .. "/" .. rel
    if readable(candidate) then
      return candidate
    end
  end
  return path
end

-- 从 rime config 读取字符串列表（如 numen/date_formats）；读取失败返回 nil
local function get_string_list(config, path)
  local ok_call, list = pcall(function()
    return config:get_list(path)
  end)
  if not ok_call or not list then
    return nil
  end
  local out = {}
  for i = 0, list.size - 1 do
    local ok_item, v = pcall(function()
      return config:get_string(path .. "/@" .. i)
    end)
    if ok_item and v then
      out[#out + 1] = v
    end
  end
  return #out > 0 and out or nil
end

local T = {}

-- 安全读取配置：部分 rime-lua 版本读取不存在的 key 会报错
local function cfg_get(config, method, path)
  local ok_call, v = pcall(function()
    return config[method](config, path)
  end)
  if ok_call then
    return v
  end
  return nil
end

function T.init(env)
  -- 整个初始化过程用 pcall 包裹，任何异常都记录为可见错误
  local ok_init, err = pcall(function()
    T.init_real(env)
  end)
  if not ok_init then
    T.core = nil
    T.init_error = "初始化异常: " .. tostring(err)
  end
end

function T.init_real(env)
  T.rates_warning = nil
  local config = env.engine.schema.config
  env.name_space = env.name_space:gsub("^*", "")
  local pattern = cfg_get(config, "get_string", "recognizer/patterns/numen")
    or cfg_get(config, "get_string", "recognizer/patterns/calculator")
  T.prefix = (pattern and pattern:match("%^.?([a-zA-Z/=]+).*")) or "V"
  T.tips = cfg_get(config, "get_string", "numen/tips") or "计算"
  T.init_error = nil
  T.core = nil

  if not ok then
    T.init_error = "加载 numen-core 失败: " .. tostring(numen)
    return
  end
  local configured = cfg_get(config, "get_string", "numen/rates_path")
  local rates_path = resolve_rates_path(configured)
    or resolve_rates_path("lua/numen/rates.json")
    or resolve_rates_path("rates.json")
    or "rates.json"
  local core_cfg = {
    rates_path = rates_path,
    base_currency = cfg_get(config, "get_string", "numen/base_currency"),
    auto_convert_currency = cfg_get(config, "get_bool", "numen/auto_convert_currency"),
    implicit_day = cfg_get(config, "get_bool", "numen/implicit_day"),
    binary_bytes = cfg_get(config, "get_bool", "numen/binary_bytes"),
  }
  -- get_string/get_bool 缺省返回 nil 时需要剔除，交给 Core 用自身默认值
  for k, v in pairs(core_cfg) do
    if v == nil then
      core_cfg[k] = nil
    end
  end
  local core, err = numen.Core.new(core_cfg)
  if not core then
    -- 汇率文件缺失时降级：仅含基准货币的空汇率表，货币换算不可用
    local base = (core_cfg.base_currency or "cny"):upper()
    core = numen.Core.new({ rates = { [base] = 1 } })
    if core then
      T.rates_warning = "未加载汇率: " .. tostring(err)
    else
      T.init_error = "引擎初始化失败: " .. tostring(err)
      return
    end
  end
  T.core = core
  T.presenter = numen.Present.new({
    date_formats = get_string_list(config, "numen/date_formats"),
    time_formats = get_string_list(config, "numen/time_formats"),
    datetime_formats = get_string_list(config, "numen/datetime_formats"),
    rmb_cn = cfg_get(config, "get_bool", "numen/rmb_cn"),
    nearby_units = cfg_get(config, "get_bool", "numen/nearby_units"),
  })
end

local function startsWith(str, start)
  return type(start) == "string" and string.sub(str, 1, string.len(start)) == start
end

function T.func(input, seg, env)
  -- 惰性初始化：返回 {T=..., P=...} 的结构下 rime-lua 不会调用 T.init，
  -- 必须在首次使用时自己完成初始化；失败后下次输入会重试
  if not T.initialized then
    T.init(env)
    T.initialized = T.core ~= nil or T.init_error == nil
  end
  if not (startsWith(input, T.prefix) or seg:has_tag("numen")) then
    return
  end
  local composition = env.engine.context.composition
  if composition:empty() then
    return
  end
  local segment = composition:back()
  segment.prompt = "〔" .. (T.tips or "计算") .. "〕"
  segment.tags = segment.tags + Set({ "numen" })

  -- 初始化失败时给出可见的错误提示（直接放在候选正文，避免被忽略）
  if not T.core then
    yield(Candidate("numen", seg.start, seg._end, "numen 错误", T.init_error or "引擎未初始化"))
    yield(Candidate("numen", seg.start, seg._end, T.init_error or "引擎未初始化", ""))
    return
  end

  local expr = input
  if startsWith(input, T.prefix) then
    expr = input:sub(#T.prefix + 1)
  end
  expr = expr:match("^%s*(.-)%s*$")
  if expr == "" then
    return
  end

  -- 出错时直接在候选正文给出原因，并附上前缀提示
  local function yield_error(msg)
    yield(Candidate("numen", seg.start, seg._end, "numen: " .. msg, expr))
  end

  local ok_eval, cands, err = pcall(T.core.evaluate, T.core, expr)
  if not ok_eval then
    yield_error("计算异常: " .. tostring(cands))
    return
  end
  if not cands then
    yield_error(tostring(err))
    return
  end
  local lines = T.presenter:format_candidates(cands)
  if #lines == 0 then
    yield_error("无结果")
    return
  end
  for _, s in ipairs(lines) do
    yield(Candidate("numen", seg.start, seg._end, s, T.rates_warning or ""))
  end
  -- 汇率缺失时额外给出可见提示候选
  if T.rates_warning then
    yield(Candidate("numen", seg.start, seg._end, "numen: " .. T.rates_warning, expr))
  end
end

-- 按键处理器：numen 段内的特殊按键处理：
--   空格  -> 写入输入串（表达式可能含空格，如 `V1usd to rmb`），而不是选词上屏
--   回车  -> 上屏当前高亮候选的结果文本，而不是原始输入 `V1+1`
--   Tab / Shift+Tab -> 向后 / 向前移动高亮候选
-- 返回值约定（rime-lua）：
--   0 = kRejected 拒绝按键（停止处理链且按键不交给引擎，会穿透到应用，严禁用于放行）
--   1 = kAccepted 已处理（停止处理链）
--   2 = kNoop     未处理（放行给下一个处理器）
local P = {}

local KEY_SPACE = 0x20
local KEY_RETURN = 0xff0d -- Return（小键盘 Enter 为 0xff8d）
local KEY_KP_ENTER = 0xff8d
local KEY_TAB = 0xff09

-- 当前段是否属于 numen
local function in_numen_segment(context)
  local composition = context.composition
  if composition:empty() then
    return nil
  end
  local segment = composition:back()
  if segment and segment:has_tag("numen") then
    return segment
  end
  return nil
end

function P.func(key, env)
  -- 只处理按下，忽略抬起
  if key:release() then
    return 2
  end
  local kc = key.keycode
  if kc ~= KEY_SPACE and kc ~= KEY_RETURN and kc ~= KEY_KP_ENTER and kc ~= KEY_TAB then
    return 2
  end
  local context = env.engine.context
  local segment = in_numen_segment(context)
  if not segment then
    return 2
  end

  if kc == KEY_SPACE then
    context:push_input(" ")
    return 1
  end

  if kc == KEY_RETURN or kc == KEY_KP_ENTER then
    -- 上屏当前高亮候选；没有候选时放行，交给默认行为（上屏原始输入）
    local cand = context:get_selected_candidate()
    if not cand then
      return 2
    end
    env.engine:commit_text(cand.text)
    context:clear()
    return 1
  end

  -- Tab：移动高亮；Shift+Tab 反向。越界时回绕到另一端。
  if key:shift() then
    local prev = segment.selected_index - 1
    if prev < 0 or not context:highlight(prev) then
      -- 尝试绕到最后一个候选
      local last = prev
      while context:highlight(last + 1) do
        last = last + 1
      end
      context:highlight(last >= 0 and last or 0)
    end
  else
    if not context:highlight(segment.selected_index + 1) then
      context:highlight(0)
    end
  end
  return 1
end

return { T = T, P = P }
