--- Civil date/time arithmetic (proleptic Gregorian, no timezone).
--- A datetime is {year, month, day, hour, min, sec}.

local M = {}

-- days from civil epoch (Howard Hinnant's algorithm), epoch = 1970-01-01
local function days_from_civil(y, m, d)
  local yy = y
  if m <= 2 then
    yy = yy - 1
  end
  local era = math.floor(yy / 400)
  if yy < 0 and yy % 400 ~= 0 then
    era = math.floor((yy - 399) / 400)
  end
  local yoe = yy - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function civil_from_days(z)
  local zz = z + 719468
  local era = math.floor(zz / 146097)
  if zz < 0 and zz % 146097 ~= 0 then
    era = math.floor((zz - 146096) / 146097)
  end
  local doe = zz - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp + 3
  if m > 12 then
    m = m - 12
    y = y + 1
  end
  return y, m, d
end

local function is_leap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function M.days_in_month(y, m)
  if m == 2 and is_leap(y) then
    return 29
  end
  return DAYS_IN_MONTH[m]
end

--- Validate a civil date.
function M.valid_date(y, m, d)
  return m >= 1 and m <= 12 and d >= 1 and d <= M.days_in_month(y, m)
end

function M.valid_time(h, mi, s)
  return h >= 0 and h <= 23 and mi >= 0 and mi <= 59 and s >= 0 and s <= 59
end

function M.datetime(y, m, d, h, mi, s)
  return { year = y, month = m, day = d, hour = h or 0, min = mi or 0, sec = s or 0 }
end

--- Current local civil datetime.
function M.now()
  local t = os.date("*t")
  return M.datetime(t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function to_seconds(dt)
  return days_from_civil(dt.year, dt.month, dt.day) * 86400 + dt.hour * 3600 + dt.min * 60 + dt.sec
end

--- Add `secs` seconds (may be negative) to a datetime.
function M.add_seconds(dt, secs)
  local total = to_seconds(dt) + secs
  local days = math.floor(total / 86400)
  local sod = total - days * 86400
  if sod < 0 then
    sod = sod + 86400
    days = days - 1
  end
  local y, m, d = civil_from_days(days)
  local h = math.floor(sod / 3600)
  local mi = math.floor((sod % 3600) / 60)
  local s = sod % 60
  return M.datetime(y, m, d, h, mi, s)
end

function M.date_eq(dt, y, m, d)
  return dt.year == y and dt.month == m and dt.day == d
end

function M.dt_eq(a, b)
  return M.date_eq(a, b.year, b.month, b.day) and a.hour == b.hour and a.min == b.min and a.sec == b.sec
end

return M
