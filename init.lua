rcbows = {}

local S = minetest.get_translator(minetest.get_current_modname())
rcbows.path = minetest.get_modpath("rcbows")
dofile(rcbows.path .. "/hud.lua")

--CONSTANTS
local DEFAULT_MAX_HEAR_DISTANCE = 10
local DEFAULT_GAIN = 0.5

local current_time = 0
local storage = minetest.get_mod_storage()

rcbows.registered_arrows = {}
rcbows.registered_items = {}
rcbows.registered_charged_items = {}

function rcbows.spawn_arrow(user, strength, itemstack)
	local pos = user:get_pos()
	pos.y = pos.y + 1.5 -- camera offset
	local dir = user:get_look_dir()
	local yaw = user:get_look_horizontal()
	local meta = itemstack:get_meta()
	local arrow = meta:get_string("rcbows:charged_arrow")
	local obj = nil
	if pos and arrow then
		obj = minetest.add_entity(pos, arrow)
	end
	if not obj then
		return
	end
	local lua_ent = obj:get_luaentity()
        if not lua_ent then
           return
        end
	lua_ent.shooter_name = user:get_player_name()
	obj:set_yaw(yaw - 0.5 * math.pi)
	local velocity = vector.multiply(dir, strength)
	obj:set_velocity(velocity)
	return true
end

function rcbows.get_charge(player)
	if not player then
		return nil
	end
	local charge_end = 0
	local player_meta = nil

	if player:is_player() then
		player_meta = player:get_meta()
		charge_end = player_meta:get_int("rcbows:charge_end")
	end
	if current_time > charge_end then
		return nil
	else
		return charge_end - current_time
	end
end

function rcbows.get_charge_max(player)
	if not player then
		return nil
	end
	local player_meta = nil
	if player:is_player() then
		player_meta = player:get_meta()
		local charge_max = player_meta:get_int("rcbows:charge_max")
		return charge_max
	end
end

function rcbows.register_bow(name, def)
	assert(type(def.description) == "string")
	assert(type(def.image) == "string")
	assert(type(def.strength) == "number")
	assert(def.uses > 0)

        local function reload_bow(itemstack, user) -- called on every right click
           local inv = user:get_inventory()
           local arrow, inventory_arrow
           if type(def.arrows) == 'table' then --more than one arrow?
              for i = 1, #def.arrows do
                 arrow = def.arrows[i]
                 inventory_arrow = minetest.registered_entities[arrow].inventory_arrow_name
                 if inv:contains_item("main", inventory_arrow) then
                    break
                 end
              end
           else
              arrow = def.arrows
              inventory_arrow = minetest.registered_entities[def.arrows].inventory_arrow_name
           end

           if not inventory_arrow then
              return
           end

           local wielded_item = user:get_wielded_item()
           local wielded_item_name = wielded_item:get_name()
           local wielded_meta = wielded_item:get_meta()
           local wielded_item_def = wielded_item:get_description()

           local player_meta = user:get_meta()
           local pname = user:get_player_name()

           local current_time = os.time(os.date("!*t"))

           if player_meta:contains("rcbows:charge_end") then
              local player_charge_end = player_meta:get_int("rcbows:charge_end")
              if current_time < player_charge_end then
                 minetest.chat_send_player(pname, "You are already charging a weapon!")
              else
                 minetest.chat_send_player(pname, "You have already charged a weapon!")
              end
              return
           end

           if not inv:contains_item("main", inventory_arrow) then
              minetest.chat_send_player(pname, "You have no suitable ammunition!")
              return
           end

           local charge_time = def.charge_time

           player_meta:set_int("rcbows:charge_end", math.floor(current_time + charge_time))
           player_meta:set_int("rcbows:charge_max", charge_time)

           rcbows.update_hud(user, charge_time)

           if def.sounds then
              local user_pos = user:get_pos()
              if not def.sounds.soundfile_draw_bow then
                 def.sounds.soundfile_draw_bow = "rcbows_draw_bow"
                 rcbows.make_sound("pos", user_pos, def.sounds.soundfile_draw_bow, DEFAULT_GAIN, DEFAULT_MAX_HEAR_DISTANCE)
              end
           end

           minetest.after(
              charge_time,
              function(user, name)
                 local current_item = user:get_wielded_item()
                 local current_meta = current_item:get_meta()
                 if current_item:get_name() == name then
                    inv:remove_item("main", inventory_arrow)
                    current_meta:set_string("rcbows:charged_arrow", arrow) --save the arrow in the meta
                    current_item:set_name(name .. "_charged")
                    user:set_wielded_item(current_item)
                    return itemstack
                 else
                    player_meta:set_string("rcbows:charge_end", "")
                 end
              end, user, name)
        end

	minetest.register_tool(name, {
		description = def.description .. " ".. S("(place to reload)"),
		inventory_image = def.image .. "^" .. def.overlay_empty,

		on_use = function() end,
		on_place = reload_bow,
		on_secondary_use = reload_bow,
	})

	if def.recipe then
		minetest.register_craft({
			output = name,
			recipe = def.recipe
		})
	end

        local function charged_on_rightclick(itemstack, user)
           local imeta = itemstack:get_meta()
           local arrow = imeta:get_string("rcbows:charged_arrow")
           imeta:set_string("rcbows:charged_arrow", "")

           local umeta = user:get_meta()
           umeta:set_string("rcbows:charge_end", "")

           itemstack:set_name(name)

           local arrow_def = rcbows.registered_arrows[arrow]
           player_api.give_item(user, arrow_def.inventory_arrow.name)

           minetest.chat_send_player(
              user:get_player_name(), "Unloaded wielded weapon."
           )

           return itemstack
        end

	minetest.register_tool(name .. "_charged", {
		description = def.description .. " " .. S("(use to fire)"),
		inventory_image = def.base_texture .. "^" ..def.overlay_charged,
		groups = {not_in_creative_inventory=1},

                -- -- Unneeded
                -- on_drop = function(itemstack, dropper, pos)
                --    local imeta = itemstack:get_meta()
                --    imeta:set_string("rcbows:charged_arrow", "")
                --    itemstack:set_name(name)

                --    local dmeta = dropper:get_meta()
                --    dmeta:set_string("rcbows:charge_end", "")

                --    return minetest.item_drop(itemstack, dropper, pos)
                -- end,

                on_place = charged_on_rightclick,
                on_secondary_use = charged_on_rightclick,

		on_use = function(itemstack, user, pointed_thing)

                        local player_meta = user:get_meta()

                        if not player_meta:contains("rcbows:charge_end") then
                           itemstack:set_name(name)
                           return itemstack
                        end

                        player_meta:set_string("rcbows:charge_end", "") -- clear the int

			if not rcbows.spawn_arrow(user, def.strength, itemstack) then
                           itemstack:set_name(name)
                           return itemstack
			end
			if def.sounds then
				local user_pos = user:get_pos()
				if not def.sounds.soundfile_fire_arrow then
					def.sounds.soundfile_fire_arrow = "rcbows_fire_arrow"
				end
				rcbows.make_sound("pos", user_pos, def.sounds.soundfile_fire_arrow, DEFAULT_GAIN, DEFAULT_MAX_HEAR_DISTANCE)
			end
			itemstack:set_name(name)
			itemstack:set_wear(itemstack:get_wear() + 0x10000 / def.uses)
			return itemstack
		end,
	})

        rcbows.registered_items[name] = true
        rcbows.registered_charged_items[name .. "_charged"] = true
end

function rcbows.register_arrow(name, def)
	rcbows.registered_arrows[name] = def
	rcbows.registered_arrows[name].name = name

	minetest.register_entity(name, {
		hp_max = 4,       -- possible to catch the arrow (pro skills)
		physical = false, -- use Raycast
		collisionbox = {-0.1, -0.1, -0.1, 0.1, 0.1, 0.1},
		visual = "wielditem",
		textures = {def.inventory_arrow.name},
		visual_size = {x = 0.2, y = 0.15},
		old_pos = nil,
		velocity = nil,
		liquidflag = nil,
		shooter_name = "",
		waiting_for_removal = false,
		inventory_arrow_name = def.inventory_arrow.name,

		on_activate = function(self)
			self.object:set_acceleration({x = 0, y = -9.81, z = 0})
		end,

		on_step = function(self, dtime)
			if self.waiting_for_removal then
				self.object:remove()
				return
			end
			local pos = self.object:get_pos()
			self.old_pos = self.old_pos or pos
			local drag_factor = def.drag_factor or 0.995 -- EVEN DRAG FACTORS OF 0.95 ARE VERY NOTICEABLE- KEEP THIS NUMBER CLOSE TO AND BELOW 1
			local velocity = self.object:get_velocity()
			self.object:set_velocity(vector.multiply(velocity, drag_factor))
			local cast = minetest.raycast(self.old_pos, pos, true, true)
			local thing = cast:next()
			while thing do
				if thing.type == "object" and thing.ref ~= self.object then
					if not thing.ref:is_player() or thing.ref:get_player_name() ~= self.shooter_name then
						thing.ref:punch(self.object, 1.0, {
							full_punch_interval = 0.5,
							damage_groups = {fleshy = def.damage, pierce = def.pierce or 0, slash = def.slash or 0, bludgeon = def.bludgeon or 0}
						})
						self.waiting_for_removal = true
						self.object:remove()
						if def.sounds then
							local thing_pos = thing.ref:get_pos()
							if not def.sounds.soundfile_hit_arrow then
								def.sounds.soundfile_hit_arrow = "rcbows_hit_arrow"
							end
							if thing_pos then
								rcbows.make_sound("pos", thing_pos, def.sounds.soundfile_hit_arrow, gain, max_hear_distance)
							end
						end

						-- no effects or not owner, nothing to do.
						-- some effects should also happen if hitting an other object. like tnt, water etc.
						if not def.effects or minetest.is_protected(pos, self.shooter_name) then
							return
						end

						rcbows.boom_effect(def, pos) -- BOOM
						rcbows.water_effect(def, pos) -- water - extinguish fires

						return
					end
				elseif thing.type == "node" then
					local name = minetest.get_node(thing.under).name
					local drawtype = minetest.registered_nodes[name]["drawtype"]
					if drawtype == 'liquid' then
						if not self.liquidflag then
							self.velocity = velocity
							self.liquidflag = true
							local liquidviscosity = minetest.registered_nodes[name]["liquid_viscosity"]
							local drag = 1/(liquidviscosity*6)
							self.object:set_velocity(vector.multiply(velocity, drag))
							self.object:set_acceleration({x = 0, y = -1.0, z = 0})
							rcbows.splash(self.old_pos, "rcbows_bubble.png")
						end
					elseif self.liquidflag then
						self.liquidflag = false
						if self.velocity then
							self.object:set_velocity(self.velocity)
						end
						self.object:set_acceleration({x = 0, y = -9.81, z = 0})
					end
					if minetest.registered_items[name].walkable then
						if not(def.no_drop) then
							minetest.item_drop(ItemStack(def.drop or def.inventory_arrow), nil, vector.round(self.old_pos))
						end
						self.waiting_for_removal = true
						self.object:remove()

						-- no effects or not owner, nothing to do.
						if not def.effects then
							return
						end

						--replace node
						if def.effects.replace_node
							and minetest.get_node(thing.above).name == "air" then
								minetest.set_node(thing.above, {name = def.effects.replace_node})
						end

						rcbows.boom_effect(def, pos) -- BOOM
						rcbows.water_effect(def, pos) -- water - extinguish fires

						return
					end
				end
				thing = cast:next()
			end
			if def.effects and def.effects.trail_particle then
				rcbows.trail(self.old_pos, pos, def.effects.trail_particle)
			end
			self.old_pos = pos
		end,
	})
	minetest.register_craftitem(def.inventory_arrow.name, {
		description = def.inventory_arrow.description,
		inventory_image = def.inventory_arrow.inventory_image,
		stack_max = def.stack_max or 99,
	})
end

--SOUND SYSTEM

function rcbows.make_sound(dest_type, dest, soundfile, gain, max_hear_distance)
	if dest_type == "object" then
		minetest.sound_play(soundfile, {object = dest, gain = gain or DEFAULT_GAIN, max_hear_distance = max_hear_distance or DEFAULT_MAX_HEAR_DISTANCE,})
	 elseif dest_type == "player" then
		local player_name = dest:get_player_name()
		minetest.sound_play(soundfile, {to_player = player_name, gain = gain or DEFAULT_GAIN, max_hear_distance = max_hear_distance or DEFAULT_MAX_HEAR_DISTANCE,})
	 elseif dest_type == "pos" then
		minetest.sound_play(soundfile, {pos = dest, gain = gain or DEFAULT_GAIN, max_hear_distance = max_hear_distance or DEFAULT_MAX_HEAR_DISTANCE,})
	end
end

--ARROW EFFECTS

function rcbows.boom_effect(def, pos)
	if def.effects.explosion and def.effects.explosion.mod then
		local mod_name = def.effects.explosion.mod
		if minetest.get_modpath(mod_name) ~= nil then
			if mod_name == "tnt" then
				tnt.boom(pos, {radius = def.effects.explosion.radius, damage_radius = def.effects.explosion.damage, entity_damage = def.effects.explosion.entity_damage, explode_center = true})
			elseif mod_name == "explosions" then
				explosions.explode(pos, {radius = def.effects.explosion.radius, strength = def.effects.explosion.damage})
			end
		end
	end
end

function rcbows.water_effect(def, pos)
	if def.effects.water then
		if def.effects.water.particles then
			rcbows.splash(pos, "rcbows_water.png")
		end
		local radius = def.effects.water.radius or 5
		local flames = minetest.find_nodes_in_area({x=pos.x -radius, y=pos.y -radius, z=pos.z -radius}, {x=pos.x+radius, y=pos.y+radius, z=pos.z+radius}, {def.effects.water.flame_node})
		if flames and #flames > 0 then
			for i=1, #flames do
				minetest.set_node(flames[i], {name="air"})
				if def.effects.water.particles then
					rcbows.splash(flames[i], "rcbows_water.png")
				end
			end
		end
	end
end

--PARTICLES EFFECTS

function rcbows.trail(old_pos, pos, trail_particle)
    minetest.add_particlespawner({
        texture = trail_particle,
        amount = 20,
        time = 0.2,
        minpos = old_pos,
        maxpos = pos,
        --minvel = {x=1, y=0, z=1},
        --maxvel = {x=1, y=0, z=1},
        --minacc = {x=1, y=0, z=1},
        --maxacc = {x=1, y=0, z=1},
        minexptime = 0.2,
        maxexptime = 0.5,
        minsize = 0.1,
        maxsize = 1.0,
        collisiondetection = false,
        vertical = false,
        glow = 14,
		animation = {type = "vertical_frames", aspect_w = 3, aspect_h = 3, length = 0.5}
    })
end

function rcbows.splash(old_pos, splash_particle)
	minetest.add_particlespawner({
		amount = 5,
		time = 1,
		minpos = old_pos,
		maxpos = old_pos,
		minvel = {x=1, y=1, z=0},
		maxvel = {x=1, y=1, z=0},
		minacc = {x=1, y=1, z=1},
		maxacc = {x=1, y=1, z=1},
		minexptime = 0.2,
		maxexptime = 0.5,
		minsize = 1,
		maxsize = 1,
		collisiondetection = false,
		vertical = false,
		texture = splash_particle,
		playername = "singleplayer"
	})
end

-- timer for charging hud
local timer = 0
minetest.register_globalstep(function(dtime)
    timer = timer + dtime
    if timer < 0.5 then
        return
    end
    timer = 0

    current_time = os.time(os.date("!*t"))
end)

-- Stop charged weapons from being moved from the hotbar
minetest.register_allow_player_inventory_action(function(player, action,
                                                         inventory,
                                                         inventory_info)
      local stack

      if action == "move" then
         local from_list = inventory_info.from_list
         local from_idx =  inventory_info.from_index
         stack = inventory:get_stack(from_list, from_idx)
      else
         -- for "put" and "take" actions
         stack = inventory_info.stack
      end

      if not stack or stack:is_empty() then
         return 0
      end

      local stack_name = stack:get_name()
      if registered_charged_items[stack_name] then
         local pname = player:get_player_name()
         minetest.chat_send_player(pname, "You can't move a charged weapon!")
         return 0
      end

      return stack:get_count()
end)

minetest.register_on_dieplayer(function(player, reason)
      local meta = player:get_meta()
      meta:set_string("rcbows:charge_end", "")
end)
