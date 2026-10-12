--- Minimal JSON decoder (objects, arrays, strings, numbers, literals).
--- Sufficient for data files like rates.json; not a streaming parser.

local M = {}

local function decode_error(s, pos, msg)
  error("json decode error at byte " .. pos .. ": " .. msg, 0)
end

local parse_value -- forward declaration

local function skip_ws(s, pos)
  local _, e = s:find("^[ \t\r\n]+", pos)
  return e and e + 1 or pos
end

local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function parse_string(s, pos)
  -- pos is at the opening quote
  local out = {}
  local i = pos + 1
  while true do
    local c = s:sub(i, i)
    if c == "" then
      decode_error(s, i, "unterminated string")
    elseif c == '"' then
      return table.concat(out), i + 1
    elseif c == "\\" then
      local e = s:sub(i + 1, i + 1)
      if e == "u" then
        local hex = s:sub(i + 2, i + 5)
        local cp = tonumber(hex, 16)
        if not cp then
          decode_error(s, i, "bad \\u escape")
        end
        out[#out + 1] = utf8.char(cp)
        i = i + 6
      else
        local r = escapes[e]
        if not r then
          decode_error(s, i, "bad escape \\" .. e)
        end
        out[#out + 1] = r
        i = i + 2
      end
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
end

local function parse_number(s, pos)
  local num_str = s:match("^-?%d+%.?%d*[eE][%+%-]?%d+", pos) or s:match("^-?%d+%.%d+", pos) or s:match("^-?%d+", pos)
  if not num_str then
    decode_error(s, pos, "bad number")
  end
  return tonumber(num_str), pos + #num_str
end

local function parse_object(s, pos)
  local obj = {}
  pos = skip_ws(s, pos + 1)
  if s:sub(pos, pos) == "}" then
    return obj, pos + 1
  end
  while true do
    pos = skip_ws(s, pos)
    if s:sub(pos, pos) ~= '"' then
      decode_error(s, pos, "expected object key")
    end
    local key
    key, pos = parse_string(s, pos)
    pos = skip_ws(s, pos)
    if s:sub(pos, pos) ~= ":" then
      decode_error(s, pos, "expected `:`")
    end
    local value
    value, pos = parse_value(s, skip_ws(s, pos + 1))
    obj[key] = value
    pos = skip_ws(s, pos)
    local c = s:sub(pos, pos)
    if c == "}" then
      return obj, pos + 1
    elseif c == "," then
      pos = pos + 1
    else
      decode_error(s, pos, "expected `,` or `}`")
    end
  end
end

local function parse_array(s, pos)
  local arr = {}
  pos = skip_ws(s, pos + 1)
  if s:sub(pos, pos) == "]" then
    return arr, pos + 1
  end
  while true do
    local value
    value, pos = parse_value(s, skip_ws(s, pos))
    arr[#arr + 1] = value
    pos = skip_ws(s, pos)
    local c = s:sub(pos, pos)
    if c == "]" then
      return arr, pos + 1
    elseif c == "," then
      pos = pos + 1
    else
      decode_error(s, pos, "expected `,` or `]`")
    end
  end
end

parse_value = function(s, pos)
  pos = skip_ws(s, pos)
  local c = s:sub(pos, pos)
  if c == '"' then
    return parse_string(s, pos)
  elseif c == "{" then
    return parse_object(s, pos)
  elseif c == "[" then
    return parse_array(s, pos)
  elseif c == "t" then
    if s:sub(pos, pos + 3) == "true" then
      return true, pos + 4
    end
  elseif c == "f" then
    if s:sub(pos, pos + 4) == "false" then
      return false, pos + 5
    end
  elseif c == "n" then
    if s:sub(pos, pos + 3) == "null" then
      return nil, pos + 4
    end
  else
    return parse_number(s, pos)
  end
  decode_error(s, pos, "unexpected character `" .. c .. "`")
end

function M.decode(s)
  local value = parse_value(s, 1)
  return value
end

--- Read and decode a JSON file. Returns (value, nil) or (nil, err).
function M.decode_file(path)
  local fh, err = io.open(path, "rb")
  if not fh then
    return nil, "cannot open `" .. tostring(path) .. "`: " .. tostring(err)
  end
  local text = fh:read("a")
  fh:close()
  local ok, value = pcall(M.decode, text)
  if not ok then
    return nil, tostring(value)
  end
  return value
end

return M
