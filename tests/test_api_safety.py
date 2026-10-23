"""Run with Python and lupa installed. Mocks cannot reproduce WoW's taint engine."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class ApiSafetyTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'Compat.lua').read_text())

    def run_lua(self, code):
        self.lua.execute(code)

    def test_all_addon_files_compile_as_lua51(self):
        for file in [*ROOT.glob('*.lua'), *ROOT.glob('Modules/*.lua')]:
            self.lua.compile(file.read_text(), name=str(file))

    def test_target_names_and_classic_without_secret_api(self):
        self.run_lua('''
            UnitExists = function() return true end
            UnitIsPlayer = function() return true end
            UnitIsUnit = function() return false end
            UnitName = function() return "Somora", "TestRealm" end
            assert(EasyMail.compat.GetTargetName() == "Somora-TestRealm")
            UnitName = function() return "Somora", nil end
            assert(EasyMail.compat.GetTargetName() == "Somora")
            UnitIsUnit = function() return true end
            assert(EasyMail.compat.GetTargetName() == nil)
        ''')

    def test_secret_target_inputs_stop_before_use(self):
        self.run_lua('''
            secret = setmetatable({}, {
                __concat = function() error("secret concatenated") end,
                __eq = function() error("secret compared") end,
            })
            issecretvalue = function(v) return rawequal(v, secret) end
            for _, stage in ipairs({"exists", "player", "self", "name", "realm"}) do
                UnitExists = function() if stage == "exists" then return secret end return true end
                UnitIsPlayer = function() if stage == "player" then return secret end return true end
                UnitIsUnit = function() if stage == "self" then return secret end return false end
                UnitName = function()
                    assert(stage ~= "exists" and stage ~= "player" and stage ~= "self")
                    if stage == "name" then return secret, "Realm" end
                    return "Somora", secret
                end
                assert(EasyMail.compat.GetTargetName() == nil)
            end
        ''')

    def test_legacy_item_lock_and_stack_preserved(self):
        self.run_lua('''
            GetContainerItemInfo = function() return 123, 20, true end
            local item = EasyMail.compat.GetContainerItemInfo(0, 1)
            assert(item.stackCount == 20 and item.isLocked == true)
            C_Container = { GetContainerItemInfo = function() return {stackCount=7, isLocked=false} end }
            assert(EasyMail.compat.GetContainerItemInfo(0, 1).stackCount == 7)
        ''')

    def test_quick_attach_leaves_blizzard_error_handlers_untouched(self):
        self.run_lua('''
            EasyMail.modules = {}
            function EasyMail:RegisterModule(name, module) self.modules[name] = module end
            local original = function() end
            UIErrorsFrame = {AddMessage=original, SetScript=function() error("Blizzard script replaced") end}
            originalErrorHandler = original
        ''')
        self.lua.execute((ROOT / 'Modules/QuickAttach.lua').read_text())
        self.run_lua('''
            EasyMail.modules.QuickAttach:OnInitialize()
            assert(UIErrorsFrame.AddMessage == originalErrorHandler)
        ''')

    def test_inbox_secret_error_ignored_and_public_error_still_stops(self):
        self.run_lua('''
            function CreateFrame()
                return {Hide=function() end, RegisterEvent=function() end,
                    SetScript=function(self, event, callback) self[event]=callback end}
            end
            EasyMail.modules = {}
            function EasyMail:RegisterModule(name, module) self.modules[name]=module end
        ''')
        # Capture the module's processor frame while loading it.
        self.run_lua('''
            local create = CreateFrame
            CreateFrame = function() processor = create() return processor end
        ''')
        self.lua.execute((ROOT / 'Modules/OpenAll.lua').read_text())
        self.run_lua('''
            local module = EasyMail.modules.OpenAll
            module.EnsureMenu = function() end
            module.GetSettings = function() return {stopOnBagsFull=true} end
            module.StopProcessing = function(self, reason) stopped=reason end
            module:OnInitialize()
            module.isProcessing = true
            local secret = {}
            issecretvalue = function(v) return rawequal(v, secret) end
            processor.OnEvent(nil, "UI_ERROR_MESSAGE", secret, secret)
            assert(stopped == nil)
            ERR_INV_FULL = "full"
            processor.OnEvent(nil, "UI_ERROR_MESSAGE", 1, "full")
            assert(stopped == "bags full")
        ''')


if __name__ == '__main__':
    unittest.main()
