--- numen CLI: evaluate expressions from argv, or an interactive REPL.
---
---   lde run cli/main.lua 1usd to rmb
---   lde run cli/main.lua          # REPL, type `quit`/`exit` to leave
---
--- Run from the `lua/` directory so that the package path and the
--- default rates.json resolve.
local numen = require("numen-core")

local function run(core, presenter, input)
  local cands, err = core:evaluate(input)
  if not cands then
    print("  error: " .. err)
    return
  end
  for _, s in ipairs(presenter:format_candidates(cands)) do
    print("  " .. s)
  end
end

local function main()
  local core, err = numen.Core.new({ rates_path = os.getenv("NUMEN_RATES_PATH") or "./rates.json" })
  if not core then
    io.stderr:write("failed to init engine: " .. tostring(err) .. "\n")
    os.exit(1)
  end
  local presenter = numen.Present.new()

  if arg and #arg > 0 then
    run(core, presenter, table.concat(arg, " "))
    return
  end

  -- REPL
  while true do
    io.write("> ")
    io.flush()
    local line = io.read()
    if not line then
      break
    end
    line = line:match("^%s*(.-)%s*$")
    local lower = line:lower()
    if lower == "quit" or lower == "exit" then
      break
    end
    if line ~= "" then
      run(core, presenter, line)
    end
  end
end

main()
