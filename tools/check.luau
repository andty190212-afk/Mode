-- Compiles every .lua file under src/ with the real Luau compiler (syntax check)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local root = process.args[1] or "src"
local failed, total = 0, 0
local function walk(dir)
	for _, name in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(name, -4) == ".lua" or string.sub(name, -5) == ".luau" then
			total += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				failed += 1
				print("FAIL " .. path .. "\n  " .. tostring(err))
			end
		end
	end
end
walk(root)
print(("checked %d files, %d failed"):format(total, failed))
if failed > 0 then process.exit(1) end
