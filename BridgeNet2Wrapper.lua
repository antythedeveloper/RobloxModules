--//Client
local Client = {}
Client.Bridges = {} :: {[string]: Client}
Client.__index = Client

function Client:FireServer(...)
	assert(IS_CLIENT, "Client.FireServer Can Only Be Called On Client!")
	self._bridge:Fire(pack(...))
end

function Client:RegisterCallback(Callback: (...any) -> any)
	assert(IS_CLIENT, "Client.RegisterCallback Can Only Be Called On Client!")
	self.OnClientEvent:Connect(Callback)
end

function Client:InvokeServer(...): any
	assert(IS_CLIENT, "Client.InvokeServer Can Only Be Called On Client!")
	local RequestID = HTTP:GenerateGUID(false):lower()
	local Control = {State = false, Returned = nil}
	local Event = Events.new(RequestID, function(...)
		local invocation, Request, Other = unpack(...)
		if invocation == "invocationClientReturn" and Request == RequestID then
			if Other and type(Other) == "table" then
				Control.Returned = unpack(Other)
			elseif not Other then
				Control.Returned = nil
			elseif Other and type(Other) ~= "table" then
				Control.Returned = Other
			end

			Control.State = true
		end
	end)

	self._bridge:Fire(pack("invocationServerRequest", RequestID, ...))

	local Position = #self.Intercepters + 1
	table.insert(self.Intercepters, Event)

	local MaxWaits = 1 -- Max Wait Time (IN SECONDS)
	MaxWaits = math.ceil(MaxWaits/0.03)
	local Waits = 0

	while Waits <= MaxWaits do
		if Control.State then
			break;
		end

		Waits += 1

		task.wait()
	end

	if not Control.Returned then
		warn("[BridgeNet2]: Server Didn't Return Anything For Invocation "..RequestID.."!")
	end

	table.remove(self.Intercepters, Position)
	Event:Disconnect()
	return Control.Returned;
end

function Client:Destroy()
	assert(IS_CLIENT, "Client.Destroy Can Only Be Called On Client!")
	self._bridge:Destroy()
	self._event:Disconnect()
	Client.Bridges[self._name] = nil;
	table.clear(self)
	setmetatable(self, nil)
end

function Client.new(Name: string): Client
	assert(IS_CLIENT, "Client.new Can Only Be Called On Client!")
	assert(type(Name) == "string", "The Name Parameter Must Be A String (Required)!")
	if Client.Bridges[Name] then return Client.Bridges[Name]; end

	local self = setmetatable({}, Client)

	self._bridge = BridgeNet2.ReferenceBridge(Name) :: Bridge
	self._name = Name :: string
	self.OnClientEvent = Events.new("ClientEventEvent-"..HTTP:GenerateGUID(false):lower()) :: Event
	self.OnClientInvoke = function(...)
		warn("[BridgeNet2_Client]: "..self._name.." lacks an invocation callback! Dropping data for the request!")
		return nil;
	end
	self.Intercepters = {} :: {Event}
	self._called = function(...)
		for _, Intercepter: Event in self.Intercepters do
			if Intercepter and typeof(Intercepter) == typeof(Events.new(...)) then
				task.spawn(Intercepter.Fire, Intercepter, ...)
			end
		end

		local invocation, request, other = unpack(...)
		if invocation == "invocationClientRequest" then
			self:FireServer("invocationServerReturn", request, pack(self.OnClientInvoke(other or nil)))
		elseif invocation ~= "invocationClientReturn" then
			self.OnClientEvent:Fire(unpack(...))
		end
	end

	self._bridge:Connect(function (...)
		task.spawn(self._called, ...)
	end)

	Client.Bridges[Name] = self;
	return self;
end

export type Client = typeof(Client.new(...))

--//Server
local Server = {}
Server.Bridges = {}
Server.__index = Server

function Server:FireClient(Player: Player, ...)
	assert(IS_SERVER, "Server.FireClient Can Only Be Called On Server!")
	assert(typeof(Player) == "Instance", "The Player Argument Must Be A Player Object!")
	assert(Player.ClassName == "Player", "The Player Argument Must Be A Player Object!")

	self._bridge:Fire(BridgeNet2.Players({Player}), pack(...))
end

function Server:FireAllClients(...)
	assert(IS_SERVER, "Server.FireAllClients Can Only Be Called On Server!")
	self._bridge:Fire(BridgeNet2.AllPlayers(), pack(...))
end

function Server:FireAllExcept(Except: Player | {Player}, ...)
	assert(IS_SERVER, "Server.FireAllExcept Can Only Be Called On Server!")
	if type(Except) == "table" then
		self._bridge:Fire(BridgeNet2.PlayersExcept(Except), pack(...))
	elseif typeof(Except) == "Instance" then
		self._bridge:Fire(BridgeNet2.PlayersExcept({Except}), pack(...))
	else
		error("The Except Argument Must Be A Table Of Players To Ignore, Or A Singular Player!")
	end
end

function Server:RegisterCallback(Callback: (Player: Player, ...any) -> any)
	assert(IS_SERVER, "Server.RegisterCallback Can Only Be Called On Server!")

	self.OnServerEvent:Connect(Callback)
end

function Server:InvokeClient(Player: Player, ...): any
	assert(IS_SERVER, "Server.InvokeClient Can Only Be Called On Server!")
	local RequestID = HTTP:GenerateGUID(false):lower()
	local Control = {State = false, Returned = nil}
	local Event = Events.new(RequestID, function(Player, ...)
		local invocation, Request, Other = unpack(...)
		if invocation == "invocationServerReturn" and Request == RequestID then

			if Other and type(Other) == "table" then
				Control.Returned = Other
			elseif not Other then
				Control.Returned = nil
			elseif Other and type(Other) ~= "table" then
				Control.Returned = Other
			end

			Control.State = true
		end
	end)

	self._bridge:Fire(BridgeNet2.Players({Player}), pack("invocationClientRequest", RequestID, ...))

	local Position = #self.Intercepters + 1
	table.insert(self.Intercepters, Event)

	local MaxWaits = 1 -- Max Wait Time (IN SECONDS)
	MaxWaits = math.ceil(MaxWaits/0.03)
	local Waits = 0

	while Waits <= MaxWaits do
		if Control.State then
			break;
		end

		Waits += 1

		task.wait()
	end

	if not Control.Returned then
		warn("[BridgeNet2]: Client Didn't Return Anything For Invocation "..RequestID.."!")
	end

	table.remove(self.Intercepters, Position)
	Event:Disconnect()

	if type(Control.Returned) == "table" then
		return unpack(Control.Returned);
	end

	return Control.Returned;
end

function Server:TogglePlayersOnly(Only: Player | {Player})
	self._playerOnly = not self._playerOnly

	if self._playerOnly then
		self._called = function(Player: Player, ...)
			if find({Only}, Player) then return; end
			for _, Intercepter in self.Intercepters do
				task.spawn(Intercepter.Fire, Intercepter, Player, ...)
			end

			local invocation, Request, Other = unpack(...)

			if invocation == "invocationServerRequest" and Request then
				self:FireClient(Player, "invocationClientReturn", Request, pack(self.OnServerInvoke(Player, Other or nil)))
			elseif invocation ~= "invocationServerReturn" then
				self.OnServerEvent:Fire(Player, unpack(...))
			end
		end
	else
		self._called = function(Player: Player, ...)
			for _, Intercepter in self.Intercepters do
				task.spawn(Intercepter.Fire, Intercepter, Player, ...)
			end

			local invocation, Request, Other = unpack(...)

			if invocation == "invocationServerRequest" and Request then
				self:FireClient(Player, "invocationClientReturn", Request, pack(self.OnServerInvoke(Player, Other or nil)))
			elseif invocation ~= "invocationServerReturn" then
				self.OnServerEvent:Fire(Player, unpack(...))
			end
		end
	end
end

function Server:Destroy()
	assert(IS_SERVER, "Server.Destroy Can Only Be Called On Server!")

	self._bridge:Destroy()
	self._event:Disconnect()
	Server.Bridges[self._name] = nil;
	table.clear(self)
	setmetatable(self, nil)
end

function Server.new(Name: string): Server
	assert(IS_SERVER, "Server.new Can Only Be Called On Server!")
	assert(type(Name) == "string", "The Name Parameter Must Be A String (Required)!")
	if Server.Bridges[Name] then return Server.Bridges[Name]; end

	local self = setmetatable({}, Server)

	self._playerOnly = false
	self._bridge = BridgeNet2.ReferenceBridge(Name) :: Bridge
	self._name = Name :: string
	self.OnServerEvent = Events.new("ServerEvent-"..HTTP:GenerateGUID(false):lower())
	self.Intercepters = {} :: {Event}
	self.OnServerInvoke = function(...)
		warn("[BridgeNet2_Server]: "..self._name.." lacks an invocation callback! Dropping data for the request!")
		return nil;
	end

	self._called = function(Player: Player, ...)
		for _, Intercepter in self.Intercepters do
			if Intercepter and typeof(Intercepter) == typeof(Events.new()) and Intercepter.Fire then
				task.spawn(Intercepter.Fire, Intercepter, Player, ...)
			end
		end

		local invocation, Request, Other = unpack(...)

		if invocation == "invocationServerRequest" and Request then
			self:FireClient(Player, "invocationClientReturn", Request, pack(self.OnServerInvoke(Player, Other or nil)))
		elseif invocation ~= "invocationServerReturn" then
			self.OnServerEvent:Fire(Player, unpack(...))
		end
	end

	self._bridge:Connect(function (...)
		task.spawn(self._called, ...)
	end)

	Server.Bridges[Name] = self;
	Server.Bridges[Name].Warned = false
	return self;
end

export type Server = typeof(Server.new(...))

--//Communication
local BridgeCommunication = {}

function BridgeCommunication.CreateUUID(): string
	return BridgeNet2.CreateUUID();
end

function BridgeCommunication.FromHex(toConvert: string): string
	return BridgeNet2.FromHex(toConvert);
end

function BridgeCommunication.ToHex(toConvert: string): string
	return BridgeNet2.ToHex(toConvert);
end

function BridgeCommunication.ToReadableHex(toConvert: string): string
	return BridgeNet2.ToReadableHex(toConvert);
end

function BridgeCommunication.NumberToBestForm(num: number): number | string
	return BridgeNet2.NumberToBestForm(num);
end

function BridgeCommunication.ReferenceIdentifier(name: string, maxWaitTime: number?): string
	return BridgeNet2.ReferenceIdentifier(name, maxWaitTime or nil);
end

function BridgeCommunication.FromCompressed(compressed: string): string?
	return BridgeNet2.FromCompressed(compressed);
end

function BridgeCommunication.FromIdentifier(identifier: string): string?
	return BridgeNet2.FromIdentifier(identifier);
end

function BridgeCommunication.ReadOutput(): {TOutputObject}
	return BridgeNet2.ReadOutput();
end

function BridgeCommunication.Server(Name: string | {string}): Server
	assert(type(Name) == "string", "The Name Parameter Must Be A String!")
	assert(IS_SERVER, "Server.new Can Only Be Called On Server!")

	return Server.new(Name);
end

function BridgeCommunication.Servers(Names: {string}): {[string]: Server}
	assert(type(Names) == "table", "The Names Parameter Must Be A Table/Array Of Strings!")
	assert(IS_SERVER, "Server.new Can Only Be Called On Server!")
	local Returns = {}

	for _, v in Names do
		Returns[v] = Server.new(v)
	end

	return Returns;
end

function BridgeCommunication.Clients(Names: {string}): {[string]: Client}
	assert(type(Names) == "table", "The Names Parameter Must Be A Table/Array Of Strings!")
	assert(IS_CLIENT, "Client.new Can Only Be Called On Client!")
	local Returns = {}

	for _, v in Names do
		Returns[v] = Client.new(v)
	end

	return Returns;
end

function BridgeCommunication.Client(Name: string | {string}): Client
	assert(type(Name) == "string", "The Name Parameter Must Be A String!")
	assert(IS_CLIENT, "Client.new Can Only Be Called On Client!")

	return Client.new(Name);
end

return BridgeCommunication;
