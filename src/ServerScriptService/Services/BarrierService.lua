-- BarrierService: the island protective barrier was REMOVED at the owner's request
-- (update 2.1). Islands are always open to visitors. The module keeps its small API so
-- the other services do not need special cases. The lab shields (LabService) are a
-- separate system and still work.
local BarrierService = {}
local S

function BarrierService.Init(registry)
	S = registry
end

function BarrierService.apply(island)
	if island.rest then
		island.rest.barrierOn = false -- old saves: switch off
	end
end

function BarrierService.canEnter()
	return true
end

function BarrierService.refreshAccess() end

function BarrierService.enforce() end

function BarrierService.Start() end

return BarrierService
