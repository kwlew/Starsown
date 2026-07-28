-- lib/utils
-- Namespace for the game's Utils toolkit. Usage:
--
--   local Utils = require "lib.utils"
--   Utils.Math.randRange(1, 10)
--
-- (This lives at lib/utils.lua rather than lib/ui/init.lua because these modules
-- resolve through plain package.path, which may not include ?/init.lua.)

return {
    Math = require "lib.utils.math",
    Audios = require "lib.utils.audios",
}
