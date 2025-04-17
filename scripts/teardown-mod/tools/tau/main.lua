local tau = {}

local function rndVec(length)
    local v = VecNormalize(Vec(math.random(-100, 100), math.random(-100, 100), math.random(-100, 100)))
    return VecScale(v, length)
end

local function rnd(mi, ma)
    return math.random(1000) / 1000 * (ma - mi) + mi
end

local function Reflect(I, N)
    return VecSub(I, VecScale(N, 2 * VecDot(N, I)))
end

local function DrawTauLaser(laserPoints)
    local laserSprite = LoadSprite("gfx/laser.png")

    local col = Vec(1, 0.75, 0.3)

    for i = 1, #laserPoints - 1 do
        local origin = laserPoints[i]
        local hitPoint = laserPoints[i + 1]
        local length = VecLength(VecSub(hitPoint, origin))
        local t = Transform(VecLerp(origin, hitPoint, 0.5))
        local xAxis = VecNormalize(VecSub(hitPoint, origin))
        local zAxis = VecNormalize(VecSub(origin, GetCameraTransform().pos))
        t.rot = QuatAlignXZ(xAxis, zAxis)
        DrawSprite(laserSprite, t, length, 0.05 + math.random() * 0.01, col[1] * 4, col[2] * 4, col[3] * 4, 1, true,
            true)
        DrawSprite(laserSprite, t, length, 0.5, col[1], col[2], col[3], 1, true, true)
        PointLight(origin, col[1], col[2], col[3], 3)
        PointLight(hitPoint, col[1], col[2], col[3], 3)
    end
end

local function Sign(number)
    if number > 0 then
        return 1
    elseif number < 0 then
        return -1
    else
        return 0
    end
end

function tau:init()
    self.LnlTool = LnLInitializeTool('vl_tau', 'MOD/tools/tau/prefab.xml', 'Tau Cannon', 4)
    self.angle = 0
    self.angVel = 0
    self.coolDown = -100
    self.smoke = 0
    self.laser = 0
    self.laserPoints = {}
    self.shootSnd = {}
    self.shootSnd2 = {}
    self.playSecondarySound = 0
    for i = 1, 1 do
        self.shootSnd[i] = LoadSound("MOD/tools/tau/shot" .. i .. ".ogg")
    end
    for i = 1, 3 do
        self.shootSnd2[i] = LoadSound("MOD/tools/tau/electro" .. i .. ".ogg")
    end
    self.oldPipePos = Vec()
    self.particleTimer = 0
    self.shape = 1
    SetInt("game.tool.vl_tau.ammo", 1800)
end

function tau:shoot(dt)
    local ct = GetCameraTransform()
    if GetBool("game.player.canusetool") and InputDown("usetool") and GetInt("game.tool.vl_tau.ammo") > 0 then
        if self.coolDown < 0 then
            local distance = 1000

            local forwardPos = TransformToParentPoint(ct, Vec(0, 0, -distance))
            local rayPos = ct.pos
            local rayDir = VecSub(forwardPos, rayPos)
            rayDir = VecNormalize(rayDir)
            self.laserPoints = {}
            self.laserPoints[1] = LnLGetBoneWorldTransform(self.LnlTool, 'gun.muzzle').pos
            local final_hit = true

            for bounceI = 1, 10 do
                local hit, hitDistance, hitNormal = QueryRaycast(rayPos, rayDir, distance)
                local hitPos = VecAdd(rayPos, VecScale(rayDir, 1000))
                if hit and hitDistance < distance then
                    hitPos = VecAdd(rayPos, VecScale(rayDir, hitDistance))
                end
                -- Paint(hitPos, 0.6, "explosion")

                if hit and hitDistance < distance then
                    self.laserPoints[1 + bounceI] = hitPos
                    local cosRefl = VecDot(VecNormalize(rayDir), VecNormalize(hitNormal))
                    rayDir = Reflect(rayDir, hitNormal)
                    rayPos = VecAdd(hitPos, VecScale(rayDir, 0.01))

                    for particleI = 1, 10 do
                        ParticleReset()
                        ParticleType('plain')
                        ParticleCollide(1, 1, 'constant', 0.1)
                        ParticleGravity(-10)
                        ParticleDrag(0.025)
                        ParticleSticky(0.1, 0.35)
                        ParticleEmissive(1)
                        ParticleStretch(100)
                        ParticleTile(4)
                        local pVel = VecScale(VecAdd(hitNormal, VecAdd(rayDir, rndVec(rnd(0.75, 1.5)))), 2)
                        ParticleAlpha(20)
                        ParticleColor(1, 0.8, 0.4, 1, 0.6, 0.1)
                        ParticleRadius(0.05)
                        SpawnParticle(rayPos, pVel, 2)
                    end

                    if cosRefl < -0.5 then
                        break
                    end
                else
                    self.laserPoints[1 + bounceI] = hitPos
                    final_hit = false
                    break
                end
            end

            self.firePos = self.laserPoints[1]
            local hitPos = self.laserPoints[#self.laserPoints - 0]
            local shootPos = self.laserPoints[#self.laserPoints - 1]
            local shootDir = VecNormalize(VecSub(hitPos, shootPos))
            shootPos = VecAdd(shootPos, VecScale(shootDir, 0.01))

            if final_hit then
                Shoot(shootPos, shootDir, "gun", 1)
            end
            PlaySound(self.shootSnd[math.random(1, #self.shootSnd)], self.laserPoints[1], 0.25)

            self.playSecondarySound = 0.1

            self.smoke = math.min(1.0, self.smoke + 0.2)
            self.coolDown = 0.25
            self.particleTimer = -0.5
            SetInt("game.tool.vl_tau.ammo", GetInt("game.tool.vl_tau.ammo") - 1)

            self.laser = 0.05
            self.angVel = self.angVel + 660
            self.angVel = Sign(self.angVel) * math.min(math.abs(self.angVel), 1000)
        end
    end

    local p = self.firePos
    if self.smoke > 0 then
        if self.particleTimer < 0.0 then
            self.particleTimer = dt + (1.0 - self.smoke) * 0.05
            local vel = VecScale(VecSub(p, self.oldPipePos), 0.5 / dt)
            vel = VecAdd(vel, Vec(0, rnd(0, 2), 0))
            ParticleReset()
            ParticleType("smoke")
            ParticleRadius(0.08, 0.15)
            ParticleAlpha(self.smoke * 0.9, 0)
            ParticleDrag(1.0)
            ParticleTile(0)
            SpawnParticle(p, VecAdd(vel, rndVec(0.1)), self.particleTimer * 50)
        end
    end

    if self.laser > 0 then
        DrawTauLaser(self.laserPoints)
    end
    self.particleTimer = self.particleTimer - dt * 550
    self.oldPipePos = p

    self.coolDown = self.coolDown - dt
    self.angle = self.angle + self.angVel * dt

    self.angVel = math.max(0, self.angVel - Sign(self.angVel) * dt * 450)
end

local function EaseOutElastic(x)
    local c4 = (2 * 3.14159) / 3

    if x == 0 then
        return 0
    end
    if x == 1 then
        return 1
    end
    return -math.pow(2, 10 * x - 10) * math.sin((x * 10 - 10.75) * c4);
end

function tau:tick(dt)
    if LnLSelected(self.LnlTool) then
        self:shoot(dt)

        local recoilFactor = math.max(0, (self.coolDown + 1.75) * 0.5)
        recoilFactor = EaseOutElastic(recoilFactor)
        local defaultPos = Vec(0.21, -0.44, -0.82)
        local defaultRot = QuatEuler(3.0, 1.9, 0.0)
        local recoilPos = Vec(0.21, -0.40, -0.52)
        local recoilRot = QuatEuler(25.0, 1.9, -4.0)

        if GetBool("game.thirdperson") then
            -- move back and down
            defaultPos[3] = defaultPos[3] + 0.2
            defaultPos[2] = defaultPos[2] - 0.2
            recoilPos[3] = recoilPos[3] + 0.2
            recoilPos[2] = recoilPos[2] - 0.2
            defaultRot = QuatEuler(0, 0, 0)
        end

        LnLSetTransformation(self.LnlTool, 'gun', Transform(VecLerp(defaultPos, recoilPos, recoilFactor),
            QuatSlerp(defaultRot, recoilRot, recoilFactor)))

        LnLSetTransformation(self.LnlTool, 'gun.charger1', Transform(Vec(), QuatEuler(0, 0, -self.angle-90)))
        LnLSetTransformation(self.LnlTool, 'gun.charger2', Transform(Vec(), QuatEuler(0, 0, -self.angle-210)))
        LnLSetTransformation(self.LnlTool, 'gun.charger3', Transform(Vec(), QuatEuler(0, 0, -self.angle-330)))

        local tp_lh = LnLGetBoneLocalTransform(self.LnlTool, 'gun.tp_lh')
        local tp_rh = LnLGetBoneLocalTransform(self.LnlTool, 'gun.tp_rh')
        SetToolHandPoseLocalTransform(tp_rh, tp_lh)

        LnLApplyRig(self.LnlTool)
    end
    self.smoke = math.max(0.0, self.smoke - dt)
    self.laser = math.max(0.0, self.laser - dt)
end

function tau:draw(dt)
end

return tau
