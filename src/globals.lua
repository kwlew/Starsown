--- Values worth changing in one place. Plain data only.
-- Safe in conf.lua: nothing here touches LÖVE.

return {
    game = {
        name = "Starsown",      -- window title, save folder, wordmark
        loveVersion = "11.5",   -- keep in sync with CI
        icon = "assets/icon/starsown-128.png",
    },

    window = {
        width = 1280,  -- first-launch size, before any saved settings
        height = 720,
    },

    links = {
        github = "https://github.com/kwlew/TD-Idle",
        discord = "https://discord.gg/HEQ9PB5UHq",
    },

    services = {
        discordAppId = "1528201797863473362",
        statsEndpoint = "https://api.kwlew.dev/stats",
    },

    world = {
        widthTiles = 100000,
        heightTiles = 64000,
        tickRate = 64, -- simulation steps per second
    },
}
