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


local gpioPorts = {5, 6, 7}
local timeoutMs = 150; -- mc

-------------------------------------------

local itemsCount = 0;

for i, port in ipairs(gpioPorts) do
    gpio.mode(port, gpio.OUTPUT)
    itemsCount = i
end

if (mytimer) then
     mytimer:unregister()
     print("stopped")
end

print("blink start")

mytimer = tmr.create()
local activeIndex = 1;

mytimer:register(
    150,
    tmr.ALARM_AUTO, 
    function (t) 
        for i, port in ipairs(gpioPorts) do
            if (i == activeIndex) then
                gpio.write(port, gpio.HIGH)
            else
                gpio.write(port, gpio.LOW)
            end
        end
        
        activeIndex = activeIndex + 1
        
        if (activeIndex > itemsCount) then
            activeIndex = 1;
        end
        
    end)

mytimer:start()


