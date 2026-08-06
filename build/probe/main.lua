local function p(...) io.stdout:write(table.concat({...}, " "), "\n") io.stdout:flush() end
p("saveDir:", love.filesystem.getSaveDirectory())
p("source getInfo:", tostring(love.filesystem.getInfo("game.love") ~= nil))

local data = love.filesystem.read("game.love")
p("read bytes:", tostring(data and #data))
p("write to save dir:", tostring(love.filesystem.write("copy.love", data)))

for _, mp in ipairs({"", "game"}) do
  local ok = love.filesystem.mount("copy.love", mp)
  p(("mount copy.love at %q -> %s"):format(mp, tostring(ok)))
  if ok then
    local probe = (mp == "" and "main.lua" or mp .. "/main.lua")
    p("   sees " .. probe .. ":", tostring(love.filesystem.getInfo(probe) ~= nil))
    p("   sees assets/lang/en.json:", tostring(love.filesystem.getInfo((mp=="" and "" or mp.."/").."assets/lang/en.json") ~= nil))
    love.filesystem.unmount("copy.love")
  end
end
os.exit(0)
