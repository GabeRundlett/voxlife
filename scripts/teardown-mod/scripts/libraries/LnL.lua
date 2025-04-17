--[[
    As of now this framework requires the latest version of
    The Automatic framework, please download and include both
]]

local getTransformTable = {
	body = GetBodyTransform,
	location = GetLocationTransform,
	shape = GetShapeWorldTransform,
	light = GetLightTransform,
	trigger = GetTriggerTransform,
	vehicle = GetVehicleTransform,
}

---@class lnl_tool: { id: string, xml: string, name: string, group: integer, lnl: { path: string, rig: { bones:table<string, table>, shapes:table<string, table<integer, table>>, transformations:table<string, table> } }}


---@param id  string
---@param xml  string
---@param name  string
---@param group  integer
---@return lnl_tool
function LnLInitializeTool(id, xml, name, group)
    local tool = {}
    tool.id = id
    tool.xml = xml
    tool.name = name
    tool.group = group

    tool.lnl = {}
    tool.lnl.path = string.format('game.tool.%s', tool.id)
    tool.lnl.rig = {
        bones = {},
        shapes = {},
        transformations = {},
    }

    RegisterTool(tool.id or 'lnl_tool', tool.name or ('LNL : Line ' .. AutoGetCurrentLine(1)), 'vox/tool/sledge.vox', tool.group or 6)
    SetBool(tool.lnl.path .. '.enabled', true)
    SetString(tool.lnl.path .. '.lnl', '')
    SetInt(tool.lnl.path .. '.ammo', 9999)
    SetInt(tool.lnl.path .. '.group', group)

	AutoDeleteHandles(LnLSpawnTool(tool))
	
    return tool
end

---@param tool lnl_tool
---@return entity_handle[]
function LnLSpawnTool(tool)
    local xml = tool.xml
    if not xml then error('xml not defined, xml = ' .. AutoToString(xml)) end

    local origin = Transform()
    local entities = Spawn(xml, origin, true, false)

    for _, ent in pairs(entities) do
        local data = {}
        local handle_type = GetEntityType(ent)

        data.handle = ent
        data.tags = AutoGetTags(data.handle)

        -- Gets the transform from the spawn origin of the weapon
        data.transform = TransformToLocalTransform(origin, getTransformTable[handle_type](data.handle))

        if handle_type == "shape" then
            local body = GetShapeBody(data.handle)
            local body_tags = AutoGetTags(body)

            local shape_parent = tool.lnl.rig.shapes[body_tags.id]
            shape_parent[#shape_parent + 1] = data
        else
            local id = data.tags.id
            tool.lnl.rig.bones[id] = data
            tool.lnl.rig.shapes[id] = {}
        end
    end

    for id, bone in pairs(tool.lnl.rig.bones) do
        local order = AutoSplit(id, '.')

        local last_id = table.concat(order, '.', 1, #order - 1)
        if last_id and tool.lnl.rig.bones[last_id] then
            bone.local_transform = TransformToLocalTransform(tool.lnl.rig.bones[last_id].transform, bone.transform)
        else
            bone.local_transform = TransformCopy(bone.transform)
        end

        tool.lnl.rig.bones[id] = bone
    end

    for bone_id, connected_shapes in pairs(tool.lnl.rig.shapes) do
        for i, shape_data in pairs(connected_shapes) do
            local parent_bone = tool.lnl.rig.bones[bone_id]
            shape_data.local_transform = TransformToLocalTransform(parent_bone.transform, shape_data.transform)

            tool.lnl.rig.shapes[bone_id][i] = shape_data
        end
    end

    tool.lnl.rig = tool.lnl.rig

    return entities
end

---@param tool lnl_tool
---@return boolean selected
---@return boolean canusetool
---@return string current_tool
function LnLSelected(tool)
    local player_selected_tool = GetString('game.player.tool')
    return player_selected_tool == tool.id, GetBool('game.player.canusetool'), player_selected_tool
end

-- function LnLWantingToGrab()
-- 	return GetPlayerPickBody() > 0 or GetPlayerGrabBody() > 0
-- end

---@param tool lnl_tool
---@param id string
---@return transform
function LnLGetBoneLocalTransform(tool, id)
	local order = AutoSplit(id, '.')
	local transform = Transform()

	for o = 1, #order do
		local bid = table.concat(order, '.', 1, o)
        local bone = tool.lnl.rig.bones[bid]
        if not bone then error(string.format('LNL : Bone not found, searched for [%s], given id [%s]', AutoToString(bid), AutoToString(id))) end
		transform = TransformToParentTransform(transform, bone.local_transform)

		local add = tool.lnl.rig.transformations[bid]
		if add then
			transform = TransformToParentTransform(transform, add)
		end
	end

	return transform
end

---@param tool lnl_tool
---@param id string
---@return transform
function LnLGetBoneWorldTransform(tool, id)
    local player_tool_body = GetToolBody()
    local player_tool_transform = GetBodyTransform(player_tool_body)
    local bone_local_transform = LnLGetBoneLocalTransform(tool, id)

    return TransformToParentTransform(player_tool_transform, bone_local_transform)
end

---@param tool lnl_tool
---@return shape_handle[]
function LnLGetShapes(tool)
    local t = {}
    for id, data_table in pairs(tool.lnl.rig.shapes) do
        AutoTableConcat(t, AutoTableSub(data_table, 'handle'))
    end
    return t
end

---@param tool lnl_tool
---@param id string
---@return shape_handle[]
function LnLGetShapesOfBone(tool, id)
    return AutoTableSub(tool.lnl.rig.shapes[id], 'handle')
end

---@param tool lnl_tool
---@param id string
---@param transformation transform
function LnLSetTransformation(tool, id, transformation)
	tool.lnl.rig.transformations[id] = transformation
end

---@param tool lnl_tool
---@param regenerate boolean?
function LnLApplyRig(tool, regenerate)
    local player_tool_body = GetToolBody()

    if LnLSelected(tool) and player_tool_body > 0 then
        if not HasTag(player_tool_body, 'lnl') or regenerate then
            SetTag(player_tool_body, 'lnl')
            for _, s in pairs(GetBodyShapes(player_tool_body)) do
                Delete(s)
            end

            LnLSpawnTool(tool)

            for bone_id, connected_shapes in pairs(tool.lnl.rig.shapes) do
                for i, shape_data in pairs(connected_shapes) do
                    SetShapeBody(shape_data.handle, player_tool_body, Transform(AutoVecOne(1 / 0)))
                end
            end

            for id, bone in pairs(tool.lnl.rig.bones) do
                Delete(bone.handle)
            end
        end

        for bone_id, connected_shapes in pairs(tool.lnl.rig.shapes) do
            local bone_transform = LnLGetBoneLocalTransform(tool, bone_id)

            for i, shape_data in pairs(connected_shapes) do
                if IsHandleValid(shape_data.handle) then
                    local shape_transform = TransformToParentTransform(bone_transform, shape_data.local_transform)
                    SetShapeLocalTransform(shape_data.handle, shape_transform)
                end
            end
        end
    end
end

---@param shapes shape_handle[]
---@param body body_handle
---@param transform transform
---@param density number
---@return shape_handle[] colliders
---@return shape_handle[] visuals
function LnLFakeScaledPhysics(shapes, body, transform, density)
    visuals = {}
    colliders = {}
    
    for _, s in pairs(shapes) do
        if IsHandleValid(s) then
            local shape_world_transform = GetShapeWorldTransform(s)
            local new_transform = TransformToLocalTransform(transform, shape_world_transform)

            local x, y, z, scale = GetShapeSize(s)
            local shape_local_size = Vec(x, y, z)
            local shape_world_size = VecScale(shape_local_size, scale)

            do -- Scaled Shape Clone - Visual
                local xml = ('<vox file="tool/wire.vox" collide="false" density="0" scale="%s"/>'):format(scale * 10)
                local visual_shape = Spawn(xml, Transform(), true, true)[1]

                CopyShapePalette(s, visual_shape)
                CopyShapeContent(s, visual_shape)

                SetShapeBody(visual_shape, body, new_transform)
                visuals[#visuals + 1] = visual_shape
            end

            if not HasTag(s, 'ignore_collider') then -- Nonscaled Shape - Collider
                local new_size = AutoVecCeil(VecScale(shape_world_size, 10))
                local offset = VecScale(new_size, -0.1)
                local centered_transform = AutoTransformOffset(new_transform, VecAdd(shape_world_size, offset))

                -- local collider_shape = CreateShape(body, Transform(), s)

                local xml = ('<vox file="tool/wire.vox" density="%s"/>'):format(density or 1)
                local collider_shape = Spawn(xml, Transform(), true, true)[1]
                SetShapeBody(collider_shape, body, Transform())


                ResizeShape(collider_shape, 0, 0, 0, new_size[1] - 1, new_size[2] - 1, new_size[3] - 1)
                SetBrush('cube', -1, 1)
                DrawShapeBox(collider_shape, 0, 0, 0, new_size[1] - 1, new_size[2] - 1, new_size[3] - 1)

                SetShapeBody(collider_shape, body, centered_transform)
                SetTag(collider_shape, 'invisible')
                colliders[#colliders + 1] = collider_shape
            end
        end
    end

    SetBodyDynamic(body, true)
    SetBodyActive(body, true)
    SetTag(body, 'unbreakable')

    return colliders, visuals
end

---Creates a Dropping Tool Effect by cloning the weapon's shapes into a new body, and creating fake colliders for them.
---@param disable boolean
---@param can_pickup boolean
---@param density number
---@return body_handle generated_body
---@return shape_handle[] colliders
---@return shape_handle[] visuals
---@return string tool_id
function LnLDropTool(disable, can_pickup, density)
    local tool_id = GetString('game.player.tool')
    local tool_body = GetToolBody()
    local tool_shapes = GetBodyShapes(tool_body)

    local tool_transform = GetBodyTransform(tool_body)
    local tool_center = AutoBodyCenter(tool_body)
    local altered_tool_transform = Transform(tool_center, tool_transform.rot)

    local new_body
    if can_pickup then
        local xml = string.format(
            '<script file="ammo.lua" param0="%s" param1="%s" param2="%s"><body tags="ammo"/></script>', 'amount=0',
            'tool=' .. tool_id, 'remain=false')
        new_body = Spawn(xml, altered_tool_transform, false, false)[2]
    else
        new_body = Spawn('<body/>', altered_tool_transform, false, false)[1]
    end

    SetTag(new_body, 'tool_id ', tool_id)

    local colliders, visuals = LnLFakeScaledPhysics(tool_shapes, new_body, altered_tool_transform, density)

    if disable then
        SetBool(string.format('game.tool.%s.enabled', tool_id), false)

        local tool_group = GetInt(AutoKey('game.tool', tool_id, 'group'))
        local next_tool = 'none'

        local lowest_index = 1 / 0

        for _, id in pairs(ListKeys('game.tool')) do
            if GetBool(AutoKey('game.tool', id, 'enabled')) then
                local next_group = GetInt(AutoKey('game.tool', id, 'group'))
                local next_index = GetInt(AutoKey('game.tool', id, 'index'))

                if tool_group == next_group then
                    if next_index < lowest_index then
                        lowest_index = next_index
                        next_tool = id
                    end
                end
            end
        end

        SetString('game.player.tool', next_tool)
    end

    return new_body, colliders, visuals, tool_id
end

---@param tool lnl_tool
---@param id string
---@return body_handle generated_body
---@return shape_handle[] colliders
---@return shape_handle[] visuals
function LnLCreateBodyFromBone(tool, id)
    local tool_body = GetToolBody()

    local tool_transform = GetBodyTransform(tool_body)
    local tool_center = AutoBodyCenter(tool_body)
    local altered_tool_transform = Transform(tool_center, tool_transform.rot)

    local new_body = Spawn('<body/>', altered_tool_transform, false, false)[1]

    local visuals, colliders = LnLFakeScaledPhysics(LnLGetShapesOfBone(tool, id), new_body, altered_tool_transform)

    return new_body, colliders, visuals
end

function LnLFOVToolTransformOffset(transform, multi)
    local t = AutoMap(GetFloat('options.gfx.fov'), 60, 120, -0.25, 0.25)
    local new = TransformCopy(transform)
    new.pos[3] = new.pos[3] - t * (multi or 1)
    return new
end