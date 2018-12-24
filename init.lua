--
--
--
--

local BOT_USERNAME = "" -- Here you set the bot username (with their tag, even if it is #0000
local BOT_PASSWORD = "" -- Here you set the bot password

local json = require("json")
local http = require("coro-http")
local api = require("fromage")

local topics = {} -- This will be loaded from the forum_data.json file

local lastMessageSentAt = os.time() -- This is for the messages needed wait time
local betweenMessagesTime = 10 -- And this too
local messages = {} -- Also this!

local translate = setmetatable({
	en = {
		thanks = {"Thank you!!"}
	},
	es = {
		thanks = {"¡¡Muchas gracias!!"}
	}
}, {
	__call = function(self, language, key)
		if self[language] ~= nil then
			return self[language][key]
		else
			return self.en[key]
		end
	end
}) -- A basic translation system (not the best one but this will help us)

local dialogflowEndpoint = { -- This is your DialogFlow project endpoint link and authentication 
	link = "https://dialogflow.googleapis.com/v2/projects/HERE_GOES_YOUR_PROJECT_NAME/agent/sessions/%s:detectIntent", -- MUST have an %s for the session
	authentication = "auth key"
}
local dialogflowValidIntents = { -- These are your DialogFlow intents, if an intent is not listed here, the bot won't answer.
	congrats = function(message, topic, response)
		local result = translate(topic.lang, "thanks")
		return result[math.random(#result)] -- Returns string (the answer message)
	end
}

local client = api() -- Starts the api class

local function dialogflowRequest(session, message, lang) -- Makes a request to the DialogFlow project
	local head, body = http.request(
		"POST",
		string.format(
			dialogflowEndpoint.link,
			session
		),
		{
			{"Content-Type", "application/json; charset=utf-8"},
			{"Authorization", "Bearer " .. dialogflowEndpoint.authentication}
		},
		json.encode({
			queryInput = {
				text = {
					text = message,
					languageCode = lang
				}
			},
			queryParams = {
				timeZone = "Africa/Casablanca" -- GMT + 0 timezone
			}
		})
	)
	
	return json.decode(body).queryResult
end

local function pumpMessages() -- Pumping of the messages queue
	if #messages > 0 and os.time() - lastMessageSentAt > betweenMessagesTime then -- if there is a message in the queue and the needed wait time is lower than the actual one
		local msg = messages[1] -- gets the first message of the queue
		messages = {table.unpack(messages, 2)} -- deletes it from the queue
		
		client.answerTopic(msg[1], msg[2]) -- sends a message with the message data
		lastMessageSentAt = os.time()
	end
end

local function sendMessage(message, location) -- Adds a message to the queue
	messages[#messages + 1] = {message, location}
end

local function readNewMessages(topic) -- Reads the new messages of a topic
	local topicData = client.getTopic(topic) -- gets the topic data
	
	if topicData.totalMessages > topic.lastSeen then -- if the topic messages quantity is greater than the seen ones...
		local lastSeenPage = math.ceil(topic.lastSeen / 20) -- calculates the last seen page
		local postMessage = "" -- creates a variable with the comment to post
		
		for page = lastSeenPage, topicData.pages do -- for every page since the last seen one
			for index = page * 20 - 19, math.min(page * 20, topicData.totalMessages) do -- for every message in the page
				if index > topic.lastSeen then -- if the client didn't seen the message
					local message = client.getMessage(index, topic) -- gets the message data
					topic.lastSeen = index -- sets the last seen message to this one
					
					if message.author ~= BOT_USERNAME then -- if the message author isn't the bot client
						if string.match(message.content, "%[([^%]%=]+)=?([^%]]*)%](.-)%[%/%1%]") == nil then -- if the message doesn't have a bbcode tag
							local dialogflowResponse = dialogflowRequest(topic.f .. "-" .. topic.t .. "-" .. index, message.content, topic.lang) -- sends a request to DialogFlow
							
							local func = dialogflowValidIntents[dialogflowResponse.intent.displayName] -- checks if the DialogFlow intent is set here
							if func ~= nil then
								local link = "https://atelier801.com/topic?f=" .. topic.f .. "&t=" .. topic.t .. "&p=" .. page .. "#m" .. index -- generates a link to the message that we'll answer
								
								postMessage = postMessage .. "[spoiler=" .. message.author .. " [url=" .. link .. "](#" .. index .. ")[/url]]" -- adds a spoiler with the link to the message and the author name
								postMessage = postMessage .. "[quote=" .. string.gsub(message.author, "%#", " ") .. "]" .. message.content .. "[/quote]" -- quotes the message
								
								postMessage = postMessage .. func(message, topic, dialogflowResponse) -- calls the function and waits an answer
								
								postMessage = postMessage .. "[/spoiler]" -- closes the spoiler
							end
						end
					end
				end
			end
		end
		
		if #postMessage > 0 then -- if the message has been set
			sendMessage(postMessage, topic) -- add it to the queue
		end
	end
end

local function saveAllTheData() -- this will save the forum table data
	local file = io.open("forum_data.json", "w+")
	file:write(json.encode(topics))
	file:close()
end

local function loadAllTheData() -- this will load the forum table data
	local file = io.open("forum_data.json", "r")
	topics = json.decode(file:read())
	file:close()
end

local function botLoop() -- this is called inside a while true loop
	pumpMessages() -- pumps the message queue
	
	for _, topic in next, topics do
		readNewMessages(topic) -- reads every new message in every topic that is listed un forum_data.json
	end
	
	saveAllTheData() -- saves all the forum table data
end

coroutine.wrap(function()
	print("Loading the topics data...")
	loadAllTheData() -- loads the data
	print("Loaded!")
	
	print("Connecting the bot...")
	client.connect(BOT_USERNAME, BOT_PASSWORD) -- connects to the client
	
	if client.isConnected() then
		print("Connected. Executing the bot!")
		while true do
			botLoop() -- executes the botLoop function
		end
		print("Loop end.")
	else
		print("Can't execute the bot.")
		print(err)
	end
	
	client.disconnect() -- disconnects the client
	print("Script end.")
	os.execute("pause >nul") -- ends the script
end)()
