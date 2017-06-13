local tsDeviceKey = "YourDeviceKeyHere"
local sleepMinutes = 30

if adc.force_init_mode(adc.INIT_ADC) then
  node.restart()
  return
end

print("Posting to thingspeak "..adc.read(0))

http.get(
    "http://api.thingspeak.com/update?api_key="..tsDeviceKey.."&field1="..adc.read(0), 
    nil, 
    function(code, data)
        tmr.delay(100 * 1000)
		node.dsleep(sleepMinutes * 60 * (1000 * 1000), 1) -- 1000 * 1000 = 1sec
    end)