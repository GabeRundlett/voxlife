-- #include "scripts/libraries/Automatic.lua"
-- #include "scripts/libraries/LnL.lua"

-- #include "tools/glock/main.lua"
-- #include "tools/revolver/main.lua"
-- #include "tools/tau/main.lua"
-- #include "tools/old.lua"

old, old_env = Loader.File("tools/old.lua")
glock, glock_env = Loader.File("tools/glock/main.lua")
revolver, revolver_env = Loader.File("tools/revolver/main.lua")
tau, tau_env = Loader.File("tools/tau/main.lua")

tools = {
    old,
    glock,
    revolver,
    tau,
}

function init()
    for i = 1, #tools do
        tools[i]:init()
    end
end

function tick(dt)
    for i = 1, #tools do
        tools[i]:tick(dt)
    end
end

function draw(dt)
    for i = 1, #tools do
        tools[i]:draw()
    end
end
