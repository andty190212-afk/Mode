-- Client-side replicated state (read-only mirror of server data)
local State = {
	player = nil,
	restaurant = nil,
	world = nil,
}

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event

function State.set(key, value)
	State[key] = value
	changed:Fire(key)
end

function State.role()
	return State.player and State.player.role or ""
end

function State.isOwner()
	return State.player ~= nil and State.player.isOwner == true
end

function State.myIsland()
	return State.player and State.player.island or 0
end

return State
