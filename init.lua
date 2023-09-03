poi={}
local storage = minetest.get_mod_storage()
local info=minetest.get_server_info()
local stprefix="POI-".. info['address']  .. '-'
local displayed_pois={}

local DISTANCE_NEAR = 256

local formspec_list = {}
poi.registered_transports={}
poi.speed=0

local selected_name

poi.last_name=nil
poi.last_pos=nil

local lpos
local etime=0

local hud_wp
local hud_info

function poi.check_vector(v)
	if not v then return false end
	for _,d in pairs({"x","y","z"}) do
		if not v[d] or not tonumber(v[d]) or minetest.is_nan(v[d]) then return false end
	end
	return true
end

function poi.getwps()
	local wp={}
	for name, _ in pairs(storage:to_table().fields) do
		if name:sub(1, string.len(stprefix)) == stprefix then
			table.insert(wp, name:sub(string.len(stprefix)+1))
		end
	end
	table.sort(wp)
	return wp
end

function poi.set_waypoint(pos, name)
	pos = ws.pos_to_string(pos)
	if not pos then return end
	storage:set_string(stprefix .. tostring(name), pos)
	return true
end

function poi.delete_waypoint(name)
	storage:set_string(stprefix .. tostring(name), '')
end

function poi.get_waypoint(name)
	return ws.string_to_pos(storage:get_string(stprefix .. tostring(name)))
end

function poi.has_wp_near(pos)
	for _,v in pairs(poi.getwps()) do
		local wpos = poi.get_waypoint(v)
		if poi.check_vector(wpos) then
			if vector.distance(pos,wpos) <= DISTANCE_NEAR then return true end
		end
	end
end

function poi.rename_waypoint(oldname, newname)
	oldname, newname = tostring(oldname), tostring(newname)
	local pos = poi.get_waypoint(oldname)
	if not pos or not poi.set_waypoint(pos, newname) then return end
	if oldname ~= newname then
		poi.delete_waypoint(oldname)
	end
	return true
end

function poi.get_quad()
	local lp=minetest.localplayer:get_pos()
	local quad=""

	if lp.z < 0 then quad="South"
	else quad="North" end

	if lp.x < 0 then quad=quad.."-west"
	else quad=quad.."-east" end

	return quad
end

local lpos = nil

local function update_speed() --to be called once a second by globalstep to get speed in nodes per second
	if minetest.localplayer then
		local cpos = minetest.localplayer:get_pos()
		if lpos and cpos then
			poi.speed = ws.round2(vector.distance(cpos,lpos),2)
		end
		lpos=cpos
	end
end

minetest.register_on_death(function()
	if minetest.localplayer then
		local name = 'Death waypoint'
		local pos  = minetest.localplayer:get_pos()
		poi.death_pos = vector.new(pos)
		poi.last_pos = pos
		poi.last_name = name
		poi.set_waypoint(pos,name)
		poi.display(pos,name)
		if minetest.settings:get_bool("death_tp") then
			minetest.after(0.5,function()
				minetest.localplayer:set_pos(poi.death_pos)
			end)
		end
	end
end)

ws.rg("DeathTP","Player","death_tp",function()end,function()end,function()end,{"autorespawn"})

function poi.set_hud_wp(pos, title)
	pos = ws.string_to_pos(pos)
	if not pos then return end
	if not title then
		title = ws.pos_to_string(pos)
	end
	poi.last_name=title
	poi.last_pos=pos
	if hud_wp then
		minetest.localplayer:hud_change(hud_wp, 'name', title)
		minetest.localplayer:hud_change(hud_wp, 'world_pos', pos)
	else
		hud_wp = minetest.localplayer:hud_add({
			hud_elem_type = 'waypoint',
			name		  = title,
			text		  = 'm',
			number		= 0x00ff00,
			world_pos	 = pos
		})
	end
	return true
end

function poi.get_nearest_name()
	local ww=poi.getwps()
	local lp=minetest.localplayer:get_pos()
	local odst=500
	local rt=false
	for k,v in pairs(ww) do
		local lwp=poi.get_waypoint(v)
		if type(lwp) == 'table' then
			local dst=vector.distance(lp,lwp)
			if dst < 500 then
				if dst < odst then
					odst=dst
					rt=v
				end
			end
		end
	end
	if not rt then rt=poi.get_quad() end
	return rt
end

local function calculate_eta(tpos,speed)
	local etatime = -1
	local dst = vector.distance(ws.dircoord(0,0,0),tpos)
	if not (poi.speed == 0) then etatime = ws.round2(dst / poi.speed / 60,2) end
	return etatime
end


function poi.set_hud_info(text)
	if type(text) ~= "string" then return end
	local lp=minetest.localplayer
	if not lp then return end
	local vspeed=lp:get_velocity()
	local etatime=calculate_eta(poi.last_pos, poi.speed)
	poi.etatime = etatime
	local ttext=text.."\nSpeed: "..poi.speed.."n/s\n"
	..ws.round2(vspeed.x,2) ..','
	..ws.round2(vspeed.y,2) ..','
	..ws.round2(vspeed.z,2) .."\n"
	.."Yaw:"..tostring(ws.round2(lp:get_yaw(),2)).."° Pitch:" ..tostring(ws.round2(lp:get_pitch(),2)).."° " .. tostring(ws.getdir())
	if poi.last_pos and poi.last_name then
		ttext=ttext .. "\n" .. poi.last_name .. "\n" .. ws.pos_to_string(poi.last_pos) .. "\n" .. "ETA" .. etatime .. " mins"
	end
	if minetest.settings:get_bool('poi_shownames') then
		ttext=ttext.."\n"..poi.get_local_name()
	end
	if hud_info then
		minetest.localplayer:hud_change(hud_info,'text',ttext)
	else
		hud_info = minetest.localplayer:hud_add({
			hud_elem_type = 'text',
			name		  = "Flight Info",
			text		  = ttext,
			number		= 0x00ff00,
			direction   = 0,
			position = {x=0,y=0.8},
			alignment ={x=1,y=1},
			offset = {x=0, y=0}
		})
	end
	return true
end

function poi.display(pos,name)
	if name == nil then name=ws.pos_to_string(pos) end
	local pos=ws.string_to_pos(pos)
	poi.set_hud_wp(pos, name)
	return true
end


function poi.display_waypoint(name)
	local pos=poi.get_waypoint(name)
	poi.last_name = name
	poi.last_pos = pos
	poi.set_hud_info(name)
	ws.aim(poi.last_pos)
	poi.display(pos,name)
	return true
end


poi.registered_transports={}
local tspeed = 20 -- speed in blocks per second
local speed=0;
local ltime=0
function poi.register_transport(name,func)
	table.insert(poi.registered_transports,{name=name,func=func})
end
function poi.display_formspec()
	local formspec = 'size[6.25,9]' ..
					 'label[0,0;Waypoint list]' ..

					 'button_exit[0,7.5;1,0.5;display;Show]' ..
					 'button[3.625,7.5;1.3,0.5;rename;Rename]' ..
					 'button[4.9375,7.5;1.3,0.5;delete;Delete]'
	local sp=0
	for k,v in pairs(poi.registered_transports) do
		formspec=formspec..'button_exit['..sp..',8.5;1,0.5;'..v.name..';'..v.name..']'
		sp=sp+0.8
	end

	formspec=formspec..'textlist[0,0.75;6,6;marker;'
	local selected = 1
	formspec_list = {}

	local waypoints = poi.getwps()


	for id, name in ipairs(waypoints) do
		if id > 1 then
			formspec = formspec .. ','
		end
		if not selected_name then
			selected_name = name
		end
		if name == selected_name then
			selected = id
		end
		formspec_list[#formspec_list + 1] = name
		formspec = formspec .. '##' .. minetest.formspec_escape(name)
	end

	formspec = formspec .. ';' .. tostring(selected) .. ']'

	if selected_name then
		local pos = poi.get_waypoint(selected_name)
		if pos then
			pos = minetest.formspec_escape(tostring(pos.x) .. ', ' ..
			tostring(pos.y) .. ', ' .. tostring(pos.z))
			pos = 'Waypoint position: ' .. pos
			formspec = formspec .. 'label[0,6.75;' .. pos .. ']'
		end
	else
		-- Draw over the buttons
		formspec = formspec .. 'button_exit[0,7.5;5.25,0.5;quit;Close dialog]' ..
			'label[0,6.75;No waypoints. Add one with ".wa".]'
	end

	-- Display the formspec
	return minetest.show_formspec('poi-csm', formspec)
end

local speed_etime = 1
minetest.register_globalstep(function(dtime)
	speed_etime = speed_etime - dtime
	if speed_etime > 0 then return end
	speed_etime = 1
	update_speed()
	if poi.last_pos then
		poi.etatime = calculate_eta(poi.last_pos, poi.speed)
	end
end)


minetest.register_on_formspec_input(function(formname, fields)
	if formname == 'poi-ignore' then
		return true
	elseif formname ~= 'poi-csm' then
		return
	end
	local name = false
	if fields.marker then
		local event = minetest.explode_textlist_event(fields.marker)
		if event.index then
			name = formspec_list[event.index]
		end
	else
		name = selected_name
	end

	if name then
		for k,v in pairs(poi.registered_transports) do
			if fields[v.name] then
				if v.func(poi.get_waypoint(name),name) then
					ws.dcm('Error with '..v.name)
					return
				end
			end
		end
		if fields.display then
			if poi.display_waypoint(name) then
				ws.dcm('Error displaying waypoint!')
				return
			end
		elseif fields.rename then
			minetest.show_formspec('poi-csm', 'size[6,3]' ..
				'label[0.35,0.2;Rename poi]' ..
				'field[0.3,1.3;6,1;new_name;New name;' ..
				minetest.formspec_escape(name) .. ']' ..
				'button[0,2;3,1;cancel;Cancel]' ..
				'button[3,2;3,1;rename_confirm;Rename]')
		elseif fields.rename_confirm then
			if fields.new_name and #fields.new_name > 0 then
				if poi.rename_waypoint(name, fields.new_name) then
					selected_name = fields.new_name
				else
					ws.dcm('Error renaming poi!')
				end
				poi.display_formspec()
			else
				ws.dcm("new name")
			end
		elseif fields.delete then
			minetest.show_formspec('poi-csm', 'size[6,2]' ..
				'label[0.35,0.25;Are you sure you want to delete this poi?]' ..
				'button[0,1;3,1;cancel;Cancel]' ..
				'button[3,1;3,1;delete_confirm;Delete]')
		elseif fields.delete_confirm then
			poi.delete_waypoint(name)
			selected_name = false
			poi.display_formspec()
		elseif fields.cancel then
			poi.display_formspec()
		elseif name ~= selected_name then
			selected_name = name
			poi.display_formspec()
		end
	elseif fields.display or fields.delete then
		ws.dcm('Please select a poi.')
	end
	return true
end)

minetest.register_chatcommand('waypoints', {
	params	  = '',
	description = 'Open the poi GUI',
	func = function(param) poi.display_formspec() end
})

ws.register_chatcommand_alias('waypoints','wp', 'wps', 'waypoint')

minetest.register_chatcommand('add_waypoint', {
	params	  = '<pos / "here" / "there"> <name>',
	description = 'Adds a waypoint.',
	func = function(param)
		local s, e = param:find(' ')
		if not s or not e then
			return false, 'Invalid syntax! See .help add_mrkr for more info.'
		end
		local pos = param:sub(1, s - 1)
		local name = param:sub(e + 1)
		if not pos then
			return false, err
		end
		if not name or #name < 1 then
			return false, 'Invalid name!'
		end
		return poi.set_waypoint(pos, name), 'Done!'
	end
})
ws.register_chatcommand_alias('add_waypoint','wa', 'add_wp')


minetest.register_chatcommand('add_waypoint_here', {
	params	  = 'name',
	description = 'marks the current position',
	func = function(param)
		local name = os.date("%Y-%m-%d %H:%M:%S")
		if tostring(param) ~= "" then name=param end
		local pos  = minetest.localplayer:get_pos()
		return poi.set_waypoint(pos, name), 'Done!'
	end
})
ws.register_chatcommand_alias('add_waypoint_here', 'wah', 'add_wph')

minetest.register_chatcommand('clear_waypoint', {
	description = 'Hides the displayed waypoint.',
	func = function(param)
		if poi.flying then poi.flying=false end
		if hud_wp then
			minetest.localplayer:hud_remove(hud_wp)
			hud_wp = nil
			return true, 'Hidden the currently displayed waypoint.'
		else
			return false, 'No waypoint is currently being displayed!'
		end
		for k,v in wps do
			minetest.localplayer:hud_remove(v)
			table.remove(k)
		end

	end,
})
ws.register_chatcommand_alias('clear_waypoint', 'cwp','cls')

minetest.register_chatcommand('wpdisplay', {
	params	  = 'position name',
	description = 'display waypoint',
	func = function(pos,name)
	  poi.display(pos,name)
	end
})
ws.register_chatcommand_alias('wpdisplay', 'wpd')

minetest.register_cheat("ShowNames", "Render", "poi_shownames")
minetest.register_cheat("POIs", "World", poi.display_formspec)
