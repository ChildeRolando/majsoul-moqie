-- Runs inside the verified ViewPai module after the native definitions.
NativeTsumogiri = NativeTsumogiri or {}
local native = NativeTsumogiri
if native.enabled == nil then native.enabled = __DEFAULT_ENABLED__ end
native.objects = native.objects or setmetatable({}, {__mode = 'k'})
native.binds = native.binds or 0
native.live_binds = native.live_binds or 0
native.disposals = native.disposals or 0
native.unknowns = native.unknowns or 0

function native.Bind(object, moqie)
    -- Called at the verified creation site holding both g and k.
    if object.area ~= GameUtility.E_MJArea.qipai then return end
    native.binds = native.binds + 1
    local live = DesktopMgr.Inst.mode == GameUtility.EMJ_Mode.play
    if live then native.live_binds = native.live_binds + 1 end
    if type(moqie) ~= 'boolean' then native.unknowns = native.unknowns + 1 end
    native.objects[object] = {moqie = moqie == true, known = type(moqie) == 'boolean', live = live}
end

if not ViewPai.__native_tsumogiri_v1 then
    ViewPai.__native_tsumogiri_v1 = true
    local original_choose = ViewPai.OnChoosed
    local original_refresh = ViewPai.RefreshColor
    local original_build = ViewPai.Build
    local original_dispose = ViewPai.Dispose

    local function eligible(object)
        local binding = native.objects[object]
        return native.enabled and binding and binding.known and binding.moqie
            and object.pai and object.area == GameUtility.E_MJArea.qipai
    end

    local function choose_dimmed(object, ...)
        local before = object.ismoqie
        object.ismoqie = true
        local ok, err = pcall(original_choose, object, ...)
        object.ismoqie = before
        if not ok then error(err, 0) end
    end

    function ViewPai:OnChoosed(...)
        if eligible(self) then return choose_dimmed(self, ...) end
        return original_choose(self, ...)
    end

    function ViewPai:RefreshColor(...)
        original_refresh(self, ...)
        if eligible(self) then return choose_dimmed(self) end
    end

    function ViewPai:Build(...)
        -- Rebinding/reuse never inherits a prior object's mark.
        native.objects[self] = nil
        return original_build(self, ...)
    end

    function ViewPai:Dispose(...)
        if native.objects[self] then native.disposals = native.disposals + 1 end
        native.objects[self] = nil
        return original_dispose(self, ...)
    end

    local function refresh_bound()
        local count = 0
        for object in pairs(native.objects) do
            if object.pai and object.area == GameUtility.E_MJArea.qipai then
                object:OnChoosed()
                count = count + 1
            else
                native.objects[object] = nil
            end
        end
        return count
    end

    function native.Toggle()
        native.enabled = not native.enabled
        local count = refresh_bound()
        return 'enabled=' .. tostring(native.enabled) .. ' refreshed=' .. count
    end

    function native.Snapshot()
        local rows, count, moqie = {}, 0, 0
        for object, binding in pairs(native.objects) do
            if object.pai and object.area == GameUtility.E_MJArea.qipai then
                count = count + 1
                if binding.known and binding.moqie then moqie = moqie + 1 end
                rows[#rows + 1] = tostring(object) .. ':' .. object.pai:ToString()
                    .. ':moqie=' .. (binding.known and tostring(binding.moqie) or 'unknown')
                    .. ':native=' .. tostring(object.ismoqie) .. ':live=' .. tostring(binding.live)
            end
        end
        table.sort(rows)
        return 'enabled=' .. tostring(native.enabled) .. ' binds=' .. native.binds
            .. ' live_binds=' .. native.live_binds .. ' disposals=' .. native.disposals
            .. ' unknowns=' .. native.unknowns .. ' active=' .. count .. ' moqie=' .. moqie
            .. '\n' .. table.concat(rows, '\n')
    end

    function native.Uninstall()
        native.enabled = false
        refresh_bound()
        ViewPai.OnChoosed = original_choose
        ViewPai.RefreshColor = original_refresh
        ViewPai.Build = original_build
        ViewPai.Dispose = original_dispose
        ViewPai.__native_tsumogiri_v1 = nil
        native.Bind, native.Toggle, native.Snapshot, native.Uninstall = nil, nil, nil, nil
        native.objects = setmetatable({}, {__mode = 'k'})
        return 'uninstalled; native callbacks and colors restored'
    end
end
