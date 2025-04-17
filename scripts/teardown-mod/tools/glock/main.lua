local function rndVec(length)
    local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
    return VecScale(v, length)
end

local function rnd(mi, ma)
    return math.random(1000) / 1000 * (ma - mi) + mi
end

local glock = {}

function glock:init()
    self.LnlTool = LnLInitializeTool('vl_glock', 'MOD/tools/glock/prefab.xml', 'Glock', 2)
    self.coolDown = 0
    self.smoke = 0
    self.shootSnd = {}
    for i = 1, 1 do
        self.shootSnd[i] = LoadSound("MOD/tools/glock/shot" .. i .. ".ogg")
    end
    self.oldPipePos = Vec()
    self.particleTimer = 0
    self.shape = 1
    SetInt("game.tool.vl_glock.ammo", 1800)
end

function glock:shoot(dt)
    local ct = GetCameraTransform()

    if GetBool("game.player.canusetool") and InputDown("usetool") and GetInt("game.tool.vl_glock.ammo") > 0 then
        if self.coolDown < 0 then
            self.firePos = LnLGetBoneWorldTransform(self.LnlTool, 'gun.muzzle').pos

            local forwardPos = TransformToParentPoint(ct, Vec(0, 0, -1000))
            local direction = VecSub(forwardPos, ct.pos)
            local distance = VecLength(direction)
            direction = VecNormalize(direction)

            local hit, hitDistance = QueryRaycast(ct.pos, direction, distance)
            if hit then
                forwardPos = TransformToParentPoint(ct, Vec(0, 0, -hitDistance))
                distance = hitDistance
            end
            local aimDir = VecNormalize(VecSub(forwardPos, self.firePos))

            Shoot(self.firePos, aimDir, "gun", 1)
            -- Light, particles and sound
            local lp = TransformToParentPoint(ct, Vec(0.25, -0.25, -2.0))
            PointLight(lp, 1, 0.7, 0.5, 3)
            PlaySound(self.shootSnd[math.random(1, #self.shootSnd)], self.firePos, 0.25)

            self.smoke = math.min(1.0, self.smoke + 0.2)
            self.coolDown = 0.3
            self.particleTimer = -0.5
            SetInt("game.tool.vl_glock.ammo", GetInt("game.tool.vl_glock.ammo") - 1)
        end
    end

    local p = self.firePos
    if self.smoke > 0 then
        if self.particleTimer < 0.0 then
            self.particleTimer = dt + (1.0 - self.smoke) * 0.05
            local vel = VecScale(VecSub(p, self.oldPipePos), 0.5 / dt)
            vel = VecAdd(vel, Vec(0, rnd(0, 2), 0))
            ParticleType("smoke")
            ParticleRadius(0.08, 0.15)
            ParticleAlpha(self.smoke * 0.9, 0)
            ParticleDrag(1.0)
            SpawnParticle(p, VecAdd(vel, rndVec(0.1)), self.particleTimer * 50)
        end
    end
    self.particleTimer = self.particleTimer - dt * 550
    self.oldPipePos = p

    self.coolDown = self.coolDown - dt
end

function glock:tick(dt)
    if LnLSelected(self.LnlTool) then
        self:shoot(dt)

        local recoilFactor = math.max(0, self.coolDown / 0.3)
        local defaultPos = Vec(0.21, -0.44, -0.92)
        local defaultRot = QuatEuler(3.0, 1.9, 0.0)
        local recoilPos = Vec(0.21, -0.40, -0.62)
        local recoilRot = QuatEuler(30.0, 1.9, -4.0)

        if GetBool("game.thirdperson") then
            -- move back and left
            defaultPos[1] = defaultPos[1] - 0.15
            defaultPos[3] = defaultPos[3] + 0.5
            recoilPos[1] = recoilPos[1] - 0.15
            recoilPos[3] = recoilPos[3] + 0.5
            defaultRot = QuatEuler(0, 0, 0)
        end

        LnLSetTransformation(self.LnlTool, 'gun', Transform(VecLerp(defaultPos, recoilPos, recoilFactor),
            QuatSlerp(defaultRot, recoilRot, recoilFactor)))

        local tp_lh = LnLGetBoneLocalTransform(self.LnlTool, 'gun.tp_lh')
        local tp_rh = LnLGetBoneLocalTransform(self.LnlTool, 'gun.tp_rh')
        SetToolHandPoseLocalTransform(tp_rh, tp_lh)

        LnLApplyRig(self.LnlTool)
    end
    self.smoke = math.max(0.0, self.smoke - dt)
end

function glock:draw()
    if GetString("game.player.tool") == "vl_glock" then
        cross = UiPixelToWorld(UiCenter(), UiMiddle())
    end
end

return glock
