local function encodeMessage (context, msg)
    msg.salt = tmr.now();
    return crypto.encrypt("AES-CBC", context.accessKey:sub(1,16), sjson.encode(msg));
end

local function decodeMessage (context, msg)
    local text = crypto.decrypt("AES-CBC", context.accessKey:sub(1,16),msg);
    text = text:gsub('%z.*', '');
    return sjson.decode(text);
end

local function sendMessage (context, fillAttrs)
    local msg = {}
    fillAttrs(msg)
    context.brokerClient:publish("/"..context.deviceToken.."/system/response", encodeMessage(context, msg), 0, 0)
end

local function runFile (context,fileName)
    sendMessage(context,function(msg)
        msg.response = "system/node/dofile/start"
        msg.name = fileName
    end)
    
    s,err=pcall(function() dofile(fileName) end)
    collectgarbage()
    
    sendMessage(context, function(msg)
        msg.response = "system/node/dofile/complete"
        msg.result = s
        msg.name = fileName
        msg.err = err
    end)
end

local function downloadFile (context, url, fileName, runAfterDownload, signature)
    print("Loading: "..fileName.. " from "..url)
    
    sendMessage(context,function(msg)
        msg.response="system/file/download/start"
        msg.name=fileName
    end)
    
    http.get(url, nil, function(code, data)
        local failed = false
        local signatureMatch = false
        
        if (code ~= 200) then
            failed = true
        end
        
        if (not failed and signature) then
            signatureMatch = (crypto.toBase64(crypto.hash("SHA512", data)) == signature)
        end
        
        if (failed or not signatureMatch) then
            print("Failed")
            collectgarbage()
            
            sendMessage(context, function(msg)
                msg.response = "system/file/download/complete"
                msg.result = false
                msg.name = fileName
            end)
            return;
        end
        
        local fd = file.open(fileName,"w+");fd:write(data);fd:close()  
        collectgarbage()
    
        print("Load complete / signed")
        
        sendMessage(context,function(msg)
            msg.response="system/file/download/complete"
            msg.result=true
            msg.name=parsedData["args"]["name"]
        end)
        
        if (runAfterDownload) then
            runFile(context,fileName)
        end
    end)
end

local function isRegisteredInInit()
    if (not file.open("init.lua","r")) then
        return false
    end
    
    local line = file.readline() 
    
    while line ~= nil do
        if (string.find(line,"require") and string.find(line,"ESPSky")) then
            file.close()
            return true
        end
        
        line=file.readline() 
    end
    
    file.close()
    
    return false
end

local ESPsky={}

ESPsky.addToInit = function (brokerAddress, brokerPort, accessKey)
    if (isRegisteredInInit()) then
        print ("Already added")
    else
        file.open("init.lua","a+")
        file.writeline("pcall(function() require(\"ESPSky\").connect(\""..brokerAddress.."\","..brokerPort..",\""..accessKey.."\") end)")
        file.close()
        print ("Done")
    end
end

ESPsky.connect = function(brokerAddress,brokerPort,accessKey)
    local context = {}
    context.brokerAddress = brokerAddress
    context.brokerPort = brokerPort
    context.accessKey = accessKey
    context.deviceToken = crypto.toBase64(crypto.hash("SHA512",accessKey)):gsub("=",""):gsub("/",""):gsub("+","")
    context.brokerClient = mqtt.Client(context.deviceToken, 5)
    context.isStartup = true
    
    local lwtMessage = {}
    lwtMessage.response="system/node/state"
    lwtMessage.message="offline"
    context.brokerClient:lwt("/"..context.deviceToken.."/system/response", encodeMessage(context,lwtMessage), 0, 0)
    
    context.brokerClient:on("message", function (conn, topic, data)
    
        if (topic ~= "/"..context.deviceToken.."/system/command") then
            return
        end
        
        parsedData = decodeMessage(context,data)
        command = parsedData["command"]
        print(command)
        
        if (command=="system/file/startup") then
            print(parsedData["args"]["url"])
            
            if (parsedData["args"]["url"] and string.len(parsedData["args"]["url"]) > 0) then
                downloadFile(
                    context,
                    parsedData["args"]["url"],
                    parsedData["args"]["name"],
                    parsedData["args"]["run"],
                    parsedData["args"]["signature"])
            elseif (parsedData["args"]["run"]) then
                runFile(context,parsedData["args"]["name"])
            end
    
        elseif (command=="system/file/download") then
            downloadFile(
                context,
                parsedData["args"]["url"],
                parsedData["args"]["name"],
                parsedData["args"]["runAfterDownload"],
                parsedData["args"]["signature"])
        
        elseif command=="system/node/ping" then
            sendMessage(context,function(msg)
                msg.response="system/node/state"
                msg.message="online"
                msg.isStartup=false
                msg.espSkyVersion=2
            end)
            
        elseif command=="system/node/restart" then
            node.restart()
            
        elseif command=="system/node/compile" then
            node.compile(parsedData["args"]["name"])
            
        elseif command=="system/node/dofile" then
            runFile(context,parsedData["args"]["name"])
            
        elseif command=="system/node/command" then
            node.input(parsedData["args"]["text"])
        
        elseif command=="system/node/chipid" then
            sendMessage(context,function(msg)
                msg.response="system/node/chipid"
                msg.chipid=node.chipid()
            end)
    
        elseif command=="system/node/heap" then
            sendMessage(context,function(msg)
                msg.response="system/node/heap"
                msg.heap=node.heap()
            end)
            
        elseif command=="system/node/fs" then
            local remaining,used,total=file.fsinfo()
            sendMessage(context,function(msg)
                msg.response="system/node/fs"
                msg.used=used
                msg.total=total
            end)
        end
    
        print("OK")
    end)
    
    local connectionTimer = tmr.create()
    
    connectionTimer:register(
        1000,
        tmr.ALARM_AUTO,
        function (t) 
            
            if not (wifi.sta.getip()) then
                return;
            end
            
            connectionTimer:unregister()
            context.brokerClient:connect(brokerAddress,brokerPort,0,1, function(conn) 
            
                print("ESPSky secure connection complete")
                
                context.brokerClient:subscribe("/"..context.deviceToken.."/system/command",0)
                
                sendMessage(context,function(msg)
                    msg.response = "system/node/state"
                    msg.message = "online"
                    msg.isStartup = context.isStartup
                    msg.espSkyVersion = 2
                end)
                
                context.isStartup = false
            end)
        end)

    connectionTimer:start()

end

return ESPsky;