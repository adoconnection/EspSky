local function encodeMessage (context, msg)
    msg.salt = tmr.now();
    return crypto.encrypt("AES-CBC", context.accessKey:sub(1, 16), sjson.encode(msg));
end

local function decodeMessage (context, msg)
    local text = crypto.decrypt("AES-CBC", context.accessKey:sub(1,16), msg);
    text = text:gsub('%z.*', '');
    return sjson.decode(text);
end

local function sendMessage (context, fillAttrs)
    local msg = {}
    fillAttrs(msg)
    context.brokerClient:publish("/"..context.deviceToken.."/system/response", encodeMessage(context, msg), 0, 0)
end

local function redirectOutput (context, enabled)
    if enabled then
        node.output(function (str)
            sendMessage(context, function(msg)
                msg.response = "system/output"
    		    msg.str = str
            end)
        end, 1)
    else
        node.output(nil)
    end
end

local function runFile (context, fileName)
	sendMessage(context, function(msg)
        msg.response = "system/node/dofile/start"
	    msg.name = fileName
    end)
	s,err = pcall(function() dofile(fileName) end)
	collectgarbage()
    sendMessage(context, function(msg)
        msg.response = "system/node/dofile/complete"
    	msg.result = s
    	msg.name = fileName
    	msg.err = err
    end)
end

local function isRegisteredInInit()
    
    if (not file.open("init.lua", "r")) then
        return false
    end
    
    local line = file.readline() 
    
    while line ~= nil do
        if (string.find(line, "require") and string.find(line, "ESPSky")) then
            file.close()
            return true
        end
        
        line = file.readline() 
    end
    
    file.close()
    return false
end

local downloader = {}

downloader.run = function(context, package)
    for i, f in ipairs(package.files) do
        if (f.autorun) then
            print("runnig: ".. f.name)
            pcall(function() runFile(context, f.name) end)
        end
    end
    collectgarbage()
    print("Package complete")
end

downloader.download = function(context, package)
    if (not package.activeFile) then
        package.activeFile = 1;
    end
    
    if (package.activeFile > package.totalFiles) then
        package.activeFile = 0;
        node.task.post(function() downloader.run(context, package); end);
        return;
    end
    
    local f = package.files[package.activeFile];
    
    if (not f.update) then
        package.activeFile = package.activeFile + 1;
        node.task.post(function() downloader.download(context, package); end);
        return;
    end
    
    print("downloading: " .. f.name);
    file.remove(f.name);
    
    sendMessage(context, function(msg)
        msg.response = "system/file/download/start"
	    msg.name = f.name
    end)

    http.get(package.baseUrl..'/files/fileparts/'..f.account..'/'..f.file, nil, function(code, data)
	    if (code ~= 200) then
	        f.parts = 0;
	        package.result = false;
	    else
	        f.activePart = 0;
	        f.parts = data + 0;
            node.task.post(function() downloader.getNextPart(context, package); end);
	    end
    end)
end
downloader.getNextPart = function(context, package)
    local f = package.files[package.activeFile];
    if (f.activePart < f.parts) then
        print("loading " .. f.name .. " part "..(f.activePart + 1).. " of "..f.parts);
        http.get(package.baseUrl..'/files/file/'..f.account..'/'..f.file..'?part='..f.activePart, nil, function(code, data)
    	    if (code ~= 200) then
    	        print("ERROR:" ..f.activePart )
    	        f.result = false
    	    else
                local fd = file.open(f.name, "a+");
                fd:write(data);
                fd:close();
                collectgarbage()
                f.activePart = f.activePart + 1;
                node.task.post(function() downloader.getNextPart(context, package); end);
    	    end
        end)
else
        print("Complete")
        sendMessage(context, function(msg)
            msg.response = "system/file/download/complete"
            msg.result = true
            msg.name = f.name
        end)
        package.activeFile = package.activeFile + 1;
        if (package.activeFile <= package.totalFiles) then
            node.task.post(function() downloader.download(context, package) end);
        else
            node.task.post(function() downloader.run(context, package) end);
        end
    end
end


local ESPsky = {}

ESPsky.addToInit = function(brokerAddress, brokerPort, accessKey)
    if (isRegisteredInInit()) then
        print ("Already added")
    else
        file.open("init.lua", "a+")
        file.writeline("pcall(function() require(\"ESPSky\").connect(\""..brokerAddress.."\", "..brokerPort..", \""..accessKey.."\") end)")
        file.close()
        print ("Done")
    end
end

ESPsky.connect = function(brokerAddress, brokerPort, accessKey)
    
    local context = {}
    context.brokerAddress = brokerAddress
    context.brokerPort = brokerPort
    context.accessKey = accessKey
    context.deviceToken = crypto.toBase64(crypto.hash("SHA512", accessKey)):gsub("=", ""):gsub("/", ""):gsub("+", "")
    context.brokerClient = mqtt.Client(context.deviceToken, 5)
    context.isStartup = true

    local lwtMessage = {}
    lwtMessage.response = "system/node/state"
    lwtMessage.message = "offline"
    context.brokerClient:lwt("/"..context.deviceToken.."/system/response", encodeMessage(context,lwtMessage), 0, 0)
    
    context.brokerClient:on("message", function(conn, topic, data)
        if (topic ~= "/"..context.deviceToken.."/system/command") then
            return
        end
        parsedData = decodeMessage(context, data)
        command = parsedData["command"]
        print(command)
        
        if (command == "system/file/package") then
            print("Package")
            downloader.download(context, parsedData["args"])
            
    	elseif command == "system/node/ping" then
            sendMessage(context, function(msg)
                msg.response = "system/node/state"
        	    msg.message = "online"
        	    msg.isStartup = false
        	    msg.espSkyVersion = 2
            end)
    		
        elseif command == "system/node/restart" then
        	node.restart()
        
        elseif command == "system/node/compile" then
        	node.compile(parsedData["args"]["name"])

        elseif command == "system/node/dofile" then
            runFile(context, parsedData["args"]["name"])
    		
    	elseif command == "system/node/command" then
    		node.input(parsedData["args"]["text"])
    
    	elseif command == "system/node/chipid" then
            sendMessage(context, function(msg)
                msg.response = "system/node/chipid"
    		    msg.chipid = node.chipid()
            end)
    
        elseif command == "system/node/heap" then
            sendMessage(context, function(msg)
                msg.response = "system/node/heap"
    		    msg.heap = node.heap()
            end)
        
        elseif command == "system/node/fs" then
            local remaining, used, total = file.fsinfo()
            sendMessage(context, function(msg)
                msg.response = "system/node/fs"
    		    msg.used = used
    		    msg.total = total
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
            
            context.brokerClient:connect(brokerAddress, brokerPort, 0, 1, function(conn) 
            	print("ESPSky secure connection complete")
            	context.brokerClient:subscribe("/"..context.deviceToken.."/system/command", 0)
            	
                sendMessage(context, function(msg)
                    msg.response = "system/node/state"
            	    msg.message = "online"
            	    msg.isStartup = context.isStartup
            	    msg.espSkyVersion = 3
                end)
        	
        	    if (context.isStartup) then
        	        redirectOutput(context, true)
    	        end
    	        
                context.isStartup = false
        
            end)
        end)

    connectionTimer:start()

end

return ESPsky;