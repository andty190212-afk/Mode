-- Laboratory tuning (levels, cycle, theft rules)
local Lab = {}

-- lab level <= restaurant stars. Upgrade is paid from the restaurant budget.
Lab.Levels = {
	{ pods = 4, luck = 0, growth = 0, price = 0 },
	{ pods = 6, luck = 5, growth = 10, price = 15000 },
	{ pods = 8, luck = 10, growth = 20, price = 50000 },
	{ pods = 10, luck = 15, growth = 30, price = 150000 },
	{ pods = 12, luck = 20, growth = 40, price = 400000 },
}
Lab.MaxPods = 12
Lab.MaxCollection = 60 -- creatures per player (pods + storage)
Lab.MaxDishes = 30

-- mandatory security cycle: the lab is protected for ClosedTime, then opens.
-- After OpenWarnTime the lab STAYS OPEN until the owner steps on the plate.
Lab.ClosedTime = 120
Lab.OpenWarnTime = 120

-- theft
Lab.StealCooldown = 20 -- per thief, between attempts
Lab.CarrySpeed = 13 -- walk speed while carrying
Lab.CarryMaxTime = 240 -- carried longer -> returns to the owner
Lab.VictimImmunity = 45 -- after a creature was stolen, this lab can't be robbed for N s
Lab.DepositRadius = 26 -- thief must bring the creature to own lab platform
Lab.IncomeTick = 5 -- seconds

Lab.ChestCooldown = 1.5

return Lab
