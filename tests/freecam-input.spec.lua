-- Exercise the production RMB ownership helper without a live Roblox client.
return function(source, returnFixture)
    local first = assert(source:find('local function freecamMouseLookAllowed()', 1, true))
    local last = assert(source:find('local function setFreecam(', first, true))
    local helper = source:sub(first, last - 1)
    assert(source:find('local looking = freecamMouseLookAllowed()', last, true),
        'freecam camera loop must use the tested RMB ownership helper')
    local code = [[
local passed = 0
local function check(value, label) assert(value, label); passed += 1 end
local Settings = {ShellRedirection = true, ShellFocusKey = Enum.UserInputType.MouseButton2}
local textbox, rmbPressed = nil, true
local mouseReads = 0
local UserInputService = {
    GetFocusedTextBox = function() return textbox end,
    IsMouseButtonPressed = function(_, button)
        assert(button == Enum.UserInputType.MouseButton2, "camera look only polls RMB")
        mouseReads += 1
        return rmbPressed
    end
}
]] .. helper .. [[
check(not freecamMouseLookAllowed(), "RMB focus owns input; camera look stays off and cursor stays free")
check(mouseReads == 0, "RMB focus short-circuits the camera mouse-read path")
Settings.ShellFocusKey = Enum.KeyCode.F
check(freecamMouseLookAllowed(), "keyboard focus leaves RMB available for camera rotation")
Settings.ShellFocusKey = Enum.UserInputType.MouseButton2
Settings.ShellRedirection = false
check(freecamMouseLookAllowed(), "disabling redirection restores normal RMB camera look")
textbox = {}
check(not freecamMouseLookAllowed(), "typing prevents camera look")
textbox = nil
rmbPressed = false
check(not freecamMouseLookAllowed(), "released RMB cannot rotate the camera")
Settings.ShellRedirection = true
Settings.ShellFocusKey = Enum.KeyCode.F
check(not freecamMouseLookAllowed(), "keyboard focus does not create camera look without RMB")
return {passed = passed, sceneMutations = false}
]]
    if returnFixture then return code end
    return assert(loadstring(code, 'freecam-input.spec'))()
end
