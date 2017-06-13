-- outside - ESP port names,  inside - lua gpio port numbers
--           _______________
--      RST |               |   TXD0                
--      ADC |     ESP12     |   RXD0
--       EN |             1 |   GPIO5
--   GPIO16 | 0           2 |   GPIO4
--   GPIO14 | 5           3 |   GPIO0
--   GPIO12 | 6           4 |   GPIO2
--   GPIO13 | 7           8 |   GPIO15
--      VCC |_______________|   GND
--
-- gpio.write(5, gpio.HIGH) -- means GPIO14

-- CONNECTION INSTRUCTIONS
-- RST --> GPIO0
-- CE --> GPIO15
-- DC --> GOPIO2
-- DIN --> GPIO13 (SPI MOSI)
-- CLK --> GPIO14 (SPI CLK)


local CE_PIN  = 8 -- GPIO15 (referred as CE or SE)
local DC_PIN  = 4 -- GPIO2 *
local RST_PIN = 3 -- GPIO0 *
local spiDisplayType = "pcd8544_84x48_hw_spi"

---------------------------------------------------------

if (statsTimer) then
	statsTimer:unregister()
end

statsTimer = tmr.create()

spi.setup(1, spi.MASTER, spi.CPOL_LOW, spi.CPHA_LOW, 8, 8)
gpio.mode(8, gpio.INPUT, gpio.PULLUP)
local disp = u8g[spiDisplayType](CE_PIN, DC_PIN, RST_PIN)


disp:setFontRefHeightExtendedText()
disp:setDefaultForegroundColor()
disp:setFontPosTop()

statsTimer:register(
    100,
    tmr.ALARM_AUTO, 
    function (t) 
        
        local remaining, used, total = file.fsinfo()
        
        disp:firstPage()

        repeat
            disp:setFont(u8g["font_6x10"])
            
            disp:drawStr(0, 0, "Heap: "..(node.heap() / 1000).."k")
            disp:drawStr(0, 10, "FS: "..used/1000 .. "/"..total / 1000 .. "k")
        until not disp:nextPage()
        
    end)

statsTimer:start()