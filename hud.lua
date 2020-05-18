local charge_hud_bar = {}

function rcbows.remove_hud(player)
   local pname = player:get_player_name()

   local _
   _ = charge_hud_bar[pname] and player:hud_remove(charge_hud_bar[pname])

   charge_hud_bar[pname] = nil
end

minetest.register_on_leaveplayer(function(player)
      rcbows.remove_hud(player)
end)

function rcbows.update_hud(player)
	local pname = player:get_player_name()
	local charge = rcbows.get_charge(player)
	local bar_idx = charge_hud_bar[pname]
	if not charge then
		rcbows.remove_hud(player)
		return
	end
	local charge_time = rcbows.get_charge_max(player)
	if not charge_time then
		rcbows.remove_hud(player)
		return
	end
	local percent = 1 - (charge / charge_time)
	if not bar_idx then
		local new_bar_idx = player:hud_add({
            hud_elem_type = "image",
			position  = {x = 0.5, y = 0.55},
            offset    = {x = 0, y = 0},
            text      = "rcbows_hud_bar.png",
            scale     = { x = percent, y = 1},
            alignment = { x = 0, y = 0 },
		})
		charge_hud_bar[pname] = new_bar_idx
	else
		player:hud_change(bar_idx, "scale", { x = percent, y = 1})
	end
end

local timer = 0
minetest.register_globalstep(function(dtime)
		timer = timer + dtime
		if timer < 1.0 then
			return
		end
		timer = 0

		for pname,_ in pairs(charge_hud_bar) do
			local player = minetest.get_player_by_name(pname)
			if player then
				rcbows.update_hud(player)
			end
		end
end)
