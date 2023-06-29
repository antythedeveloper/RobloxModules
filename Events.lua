local Event = {} :: Event
Event.Events = {} :: {Event}
Event.__index = Event

function Event:Fire(...): ()
	local self: Event = self
	
	if self then
		table.insert(self._Outgoing, pack(...))
	end
end

function Event:Connect(Callback: Callback, SelfDestruct: boolean?): string?
	local self: Event = self

	if self then
		local Id = HTTP:GenerateGUID(false):lower()
		if SelfDestruct == nil then
			SelfDestruct = false
		end

		self._Callbacks[Id] = {Callback = Callback, SelfDestruct = SelfDestruct or false}

		return Id;
	end
end

function Event:DisconnectAll(FireRemainingData: boolean?): ()
	local self: Event = self
	
	if self then
		if FireRemainingData then
			for i, Outgoing: Outgoing in self._Outgoing do
				for Id: string, Callback: Connection in self._Callbacks do
					if type(Callback.Callback) == "function" then
						task.spawn(Callback.Callback, unpack(Outgoing));

						if Callback.SelfDestruct then
							self._Callbacks[Id] = nil
						end
					end
				end

				table.remove(self._Outgoing, i)
			end
		end

		self._Outgoing = {}
		self._Callbacks = {}
	end
end

function Event:_ConnectWait(Callback: Callback): string?
	local self: Event = self
	
	if self then
		local Id = HTTP:GenerateGUID(false):lower()

		self._Callbacks[Id] = {Callback = function(...) 
			Callback(Id, ...)
		end, SelfDestruct = true}

		return Id;
	end
end

function Event:Disconnect(Id: string): ()
	local self: Event = self
	
	if self then
		if not Id then
			self:DisconnectAll()
		else
			assert(self._Callbacks[Id], Id.." is not a valid Id!")

			self._Callbacks[Id] = nil
		end
	end
end

function Event:Destroy(): ()
	local self: Event = self
	
	if self then
		if self._NameChange then
			self._NameChange:Disconnect()
		end
		Event.Events[self.Name] = nil
		self._PostSimulation:Disconnect()

		for i, Outgoing: Outgoing in self._Outgoing do
			for Id: string, Callback: Connection in self._Callbacks do
				if type(Callback.Callback) == "function" then
					task.spawn(Callback.Callback, unpack(Outgoing));

					if Callback.SelfDestruct then
						self._Callbacks[Id] = nil
					end
				end
			end

			table.remove(self._Outgoing, i)
		end

		table.clear(self)
		setmetatable(self, nil)
	end
end

function Event:Wait(): ...any
	local self: Event = self
	
	if self then
		local Thread = coroutine.running();

		self:_ConnectWait(function (Id, ...)
			task.spawn(Thread, ...)
		end)

		return coroutine.yield();
	end
end

function Event:Once(Callback: Callback): (...any)
	local self: Event = self
	
	self:Connect(Callback, true)
end

function Event:Invoke(...): ...any
	local self: Event = self
	
	if self.OnInvoke and type(self.OnInvoke) == "function" then
		return self.OnInvoke(...);
	end
	
	return nil;
end

function Event.new(Name: string?, ListenForChange: boolean?): Event
	if ListenForChange == nil then
		ListenForChange = true 
	end
	
	if Event.Events[Name] then
		return Event.Events[Name] :: Event;
	end
	
	local self = setmetatable({}, Event)

	self._Id = HTTP:GenerateGUID(false):lower()
	self.Name = Name or self._Id
	self.OnInvoke = nil :: Callback?
	self._LastName = self.Name
	self._Callbacks = {} :: {[string]: {["Callback"]: Callback, SelfDestruct: boolean?}}
	self._Outgoing = {} :: Outgoing
	self._Incoming = {} :: {Event}
	self._Destroying = false
	self._PostSimulation = RS.PostSimulation:Connect(function ()
		if self then
			for i, Outgoing: Outgoing in self._Outgoing do
				task.spawn(function ()
					for Id: string, Callback: Connection in self._Callbacks do
						if type(Callback.Callback) == "function" then
							task.spawn(Callback.Callback, unpack(Outgoing));

							if Callback.SelfDestruct then
								self._Callbacks[Id] = nil
							end
						end
					end

					table.remove(self._Outgoing, i)
				end)
			end
		end
	end)

	task.spawn(function ()
		if ListenForChange == true then
			self._NameChange = Utilities.Changed(function ()
				return self.Name;
			end, nil, Event.new(nil, false))

			self._NameChange:Connect(function ()
				if self then
					Event.Events[self._LastName] = nil
					Event.Events[self.Name] = self
					self._LastName = self.Name
				end
			end)
		end
	end)
	
	Event.Events[self.Name] = self
	return self;
end


function Event:FindFirstEvent(EventName: string): Event | nil
	assert(type(EventName) == "string", "The Name parameter is required and must be a string!")

	return Event.Events[EventName];
end

function Event:WaitForEvent(EventName: string, TimeOut: number?, RunWithout: boolean?): Event | nil
	assert(type(EventName) == "string", "The Name parameter is required and must be a string!")
	local MaxTime = TimeOut or 3

	local Thread = coroutine.running();

	task.spawn(function ()
		local EndTime = os.time() + MaxTime
		local StartTime = EndTime - MaxTime
		while os.time() <= EndTime do

			if Event.Events[EventName] then 
				task.wait() 
				break; 
			end

			task.wait()
		end

		if Event.Events[EventName] then
			task.spawn(Thread, Event.Events[EventName]);
		else
			warn("Event:WaitForChild could not return the event named '"..EventName.."' within "..MaxTime.." seconds!")

			if RunWithout then
				task.spawn(Thread, nil)
			end
		end
	end)

	return coroutine.yield();
end

export type Event = typeof(Event.new("", false))

return Event
