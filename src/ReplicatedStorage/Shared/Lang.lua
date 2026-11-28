-- Restaurant Island Tycoon - client-side translation (Russian source text -> English)
-- The game is written in Russian. For English players every visible text is translated
-- on the client: first as a whole string, then piece by piece (longest phrases first),
-- so texts glued together from several parts (numbers, names) are translated too.
-- Dictionary: Shared/LangEn.lua (generated from tools/lang/en.tsv).

local Lang = {}

local dict = require(script.Parent.LangEn)

Lang.current = "ru"

-- keys sorted by length (longest first) for piece-by-piece replacement
local keys = {}
for k in pairs(dict) do
	table.insert(keys, k)
end
table.sort(keys, function(a, b)
	if #a ~= #b then
		return #a > #b
	end
	return a < b
end)

local CYR = "[\208\209]" -- UTF-8 lead bytes of Cyrillic letters

local function hasCyrillic(s: string): boolean
	return string.find(s, CYR) ~= nil
end

-- is there a Cyrillic letter right before byte position i (exclusive)?
local function cyrBefore(s: string, i: number): boolean
	if i < 3 then
		return false
	end
	local b1, b2 = string.byte(s, i - 2, i - 1)
	return (b1 == 208 or b1 == 209) and b2 >= 128 and b2 <= 191
end

local function cyrAt(s: string, i: number): boolean
	local b = string.byte(s, i)
	return b == 208 or b == 209
end

local function startsWithLetter(k: string): boolean
	return cyrAt(k, 1)
end

local function endsWithLetter(k: string): boolean
	return #k >= 2 and cyrBefore(k, #k + 1)
end

local function replacePieces(s: string): string
	for n, k in ipairs(keys) do
		if n % 64 == 0 and not hasCyrillic(s) then
			break
		end
		local from = 1
		while true do
			local a, b = string.find(s, k, from, true)
			if not a then
				break
			end
			local okLeft = not (startsWithLetter(k) and cyrBefore(s, a))
			local okRight = not (endsWithLetter(k) and cyrAt(s, b + 1))
			if okLeft and okRight then
				local en = dict[k]
				s = string.sub(s, 1, a - 1) .. en .. string.sub(s, b + 1)
				from = a + #en
			else
				from = b + 1
			end
		end
	end
	return s
end

local cache = {}
local cacheSize = 0

function Lang.translate(s: string): string
	if Lang.current ~= "en" or type(s) ~= "string" or s == "" or not hasCyrillic(s) then
		return s
	end
	local hit = cache[s]
	if hit then
		return hit
	end
	local out = dict[s]
	if not out then
		local trimmed = string.match(s, "^%s*(.-)%s*$")
		out = trimmed and dict[trimmed]
		if out then
			out = string.gsub(s, "^(%s*).-(%s*)$", function(l, r)
				return l .. out .. r
			end)
		else
			out = replacePieces(s)
		end
	end
	if cacheSize > 6000 then
		cache, cacheSize = {}, 0
	end
	cache[s] = out
	cacheSize += 1
	return out
end

-- Russian-speaking locales keep the original text, everyone else gets English
function Lang.fromLocale(locale: string?): string
	locale = string.lower(locale or "")
	for _, p in ipairs({ "ru", "uk", "be", "kk", "ky", "uz", "tg", "hy", "az", "ka" }) do
		if string.sub(locale, 1, #p) == p then
			return "ru"
		end
	end
	return "en"
end

return Lang
