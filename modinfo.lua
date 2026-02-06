-- This information tells other players more about the mod
name = "Beequeen Hive"
description = "Port of the DST Beequeen and Gigantic Hive"
author = "Alberto Pietralunga"

version = "1.0.1"
forumthread = ""

api_version = 6
dont_starve_compatible      = false
reign_of_giants_compatible  = true
shipwrecked_compatible      = true
hamlet_compatible           = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

-- Configs
local function simpleopt(x)
	return {description = x, data = x}
end

local function append(t, x)
	t[#t + 1] = x
	return t
end

local function prepend(t, x)
    for i = #t, 1, -1 do
        t[i + 1] = t[i]
    end
    t[1] = x
    return t
end

local function range(a, b, step)
	local opts = {}
	for x = a, b, step do
		append(opts, simpleopt(x))
	end
	if #opts > 0 then
		local fdata = opts[#opts].data
		if fdata < b and fdata + step - b < 1e-10 then
			append(opts, simpleopt(b))
		end
	end
	return opts
end