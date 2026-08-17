--!native
--!optimize 2
--!nocheck

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")

local Store = {}
Store.__index = Store

local Session = {}
Session.__index = Session

local Transaction = {}
Transaction.__index = Transaction

function now(): number 
	return os.clock()
end

function clone(value)
	if typeof(value) ~= "table" then return value end
	local out = {}
	for k,v in pairs(value) do out[clone(k)] = clone(v) end
	return out
end

function pathParts(path)
	if typeof(path) == "table" then return path end
	local out = {}
	for part in string.gmatch(tostring(path), "[^%.]+") do table.insert(out, part) end
	return out
end

function pathString(path)
	local p = pathParts(path)
	local out = table.create(#p)
	for i,v in ipairs(p) do out[i] = tostring(v) end
	return table.concat(out, ".")
end

function getAt(data, path)
	local p = pathParts(path)
	local cur = data
	for _,key in ipairs(p) do
		if typeof(cur) ~= "table" then return nil end
		cur = cur[key]
		if cur == nil then return nil end
	end
	return cur
end

function setAt(data, path, value)
	local p = pathParts(path)
	if #p == 0 then return false end
	local cur = data
	for i=1,#p-1 do
		local key = p[i]
		if typeof(cur[key]) ~= "table" then cur[key] = {} end
		cur = cur[key]
	end
	cur[p[#p]] = value
	return true
end

function deleteAt(data, path)
	local p = pathParts(path)
	if #p == 0 then return false end
	local cur = data
	for i=1,#p-1 do
		cur = cur[p[i]]
		if typeof(cur) ~= "table" then return false end
	end
	cur[p[#p]] = nil
	return true
end

function deepEqual(a,b,seen)
	if a == b then return true end
	if typeof(a) ~= typeof(b) then return false end
	if typeof(a) ~= "table" then return false end
	seen = seen or {}
	seen[a] = seen[a] or {}
	if seen[a][b] then return true end
	seen[a][b] = true
	for k,v in pairs(a) do if not deepEqual(v,b[k],seen) then return false end end
	for k,v in pairs(b) do if not deepEqual(a[k],v,seen) then return false end end
	return true
end

function tableSize(t)
	local n=0
	if typeof(t)=="table" then for _ in pairs(t) do n+=1 end end
	return n
end

function checksum(value)
	local s = HttpService:JSONEncode(value)
	local h = 2166136261
	for i=1,#s do
		h = bit32.bxor(h, string.byte(s,i))
		h = (h * 16777619) % 4294967296
	end
	return h
end

function isArray(t)
	if typeof(t) ~= "table" then return false end
	local n=0
	for k in pairs(t) do
		if typeof(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
		n = math.max(n,k)
	end
	for i=1,n do if t[i] == nil then return false end end
	return true
end

function serializeBuffer(value, b)
	local kind = typeof(value)
	if kind=="nil" then buffer.writeu8(b, buffer.len(b), 0); return end
end

function encode(value)
	local payload = HttpService:JSONEncode(value)
	local b = buffer.create(#payload + 16)
	for i=1,#payload do buffer.writeu8(b,i-1,string.byte(payload,i)) end
	return b, checksum(value)
end

function decode(b)
	local chars = table.create(buffer.len(b))
	for i=0,buffer.len(b)-1 do chars[i+1]=string.char(buffer.readu8(b,i)) end
	local value = HttpService:JSONDecode(table.concat(chars))
	return value
end

local Type = {}

function Type.Check(value, rule, path, errors)
	errors = errors or {}
	if not rule then return errors end
	local actual = typeof(value)
	if rule.Type and actual ~= rule.Type then
		table.insert(errors, (path or "<root>")..": expected "..rule.Type..", got "..actual)
		return errors
	end
	if rule.Type=="number" then
		if not rule.AllowNaN and value ~= value then table.insert(errors,path..": NaN") end
		if rule.Min and value < rule.Min then table.insert(errors,path..": below minimum") end
		if rule.Max and value > rule.Max then table.insert(errors,path..": above maximum") end
		if rule.Integer and value % 1 ~= 0 then table.insert(errors,path..": must be integer") end
	end
	if rule.Type=="string" then
		if rule.MinLength and #value < rule.MinLength then table.insert(errors,path..": too short") end
		if rule.MaxLength and #value > rule.MaxLength then table.insert(errors,path..": too long") end
	end
	if rule.Enum then
		local valid=false
		for _,x in ipairs(rule.Enum) do if deepEqual(x,value) then valid=true break end end
		if not valid then table.insert(errors,path..": enum violation") end
	end
	if rule.Type=="table" and typeof(value)=="table" then
		if rule.ArrayOnly and not isArray(value) then table.insert(errors,path..": expected array") end
		if rule.ArrayOf then
			for i,v in ipairs(value) do Type.Check(v,rule.ArrayOf,path.."["..i.."]",errors) end
		end
		if rule.Children then
			for k,r in pairs(rule.Children) do
				local child=value[k]
				if child==nil and r.Required then
					table.insert(errors,path.."."..tostring(k)..": required")
				elseif child~=nil then
					Type.Check(child,r,path.."."..tostring(k),errors)
				end
			end
		end
	end
	return errors
end

function reconcile(data, template)
	if typeof(template) ~= "table" then return data == nil and template or data end
	if typeof(data) ~= "table" then data = {} end
	for k,v in pairs(template) do
		if data[k] == nil then data[k] = clone(v)
		elseif typeof(v)=="table" then data[k] = reconcile(data[k],v) end
	end
	return data
end

function diff(a,b,path,out)
	out=out or {}; path=path or {}
	if deepEqual(a,b) then return out end
	if typeof(a)~="table" or typeof(b)~="table" then
		table.insert(out,{Operation="Replace",Path=clone(path),Before=clone(a),After=clone(b)})
		return out
	end
	local keys={}
	for k in pairs(a) do keys[k]=true end
	for k in pairs(b) do keys[k]=true end
	for k in pairs(keys) do
		local p=clone(path); table.insert(p,k)
		if a[k]==nil then table.insert(out,{Operation="Add",Path=p,After=clone(b[k])})
		elseif b[k]==nil then table.insert(out,{Operation="Remove",Path=p,Before=clone(a[k])})
		else diff(a[k],b[k],p,out) end
	end
	return out
end

function transient(message)
	message=tostring(message):lower()
	return message:find("thrott") or message:find("timeout") or message:find("429") or message:find("500") or message:find("502") or message:find("503") or message:find("504")
end

function Session:IsActive() 
	return self.Active == true
end

function Session:Insert(path,value)
	local list=self:Get(path)
	if typeof(list) ~="table" then
		return false,"NOT_TABLE"
	end
	return self.Store:_mutate(self,"Insert",path,value)
end

function Session:Transaction(fn)
	return self.Store:_transaction(self,fn)
end

function Session:Snapshot()
	return clone(self.Data)
end

function Session:Restore(snapshot)
	if typeof(snapshot)~="table" then return false,"INVALID_SNAPSHOT" end
	return self.Store:_replace(self,snapshot,"Restore")
end

function Session:Diff(other)
	return diff(self.Data,other)
end

function Session:Patch(patches)
	return self:Transaction(function(tx)
		for _,p in ipairs(patches) do
			local op=p.Op or p.Operation
			if op=="Set" or op=="Replace" or op=="Add" then tx:Set(p.Path,p.Value)
			elseif op=="Delete" or op=="Remove" then tx:Delete(p.Path)
			elseif op=="Increment" then tx:Increment(p.Path,p.Amount or 1)
			elseif op=="Insert" then tx:Insert(p.Path,p.Value)
			else error("Unknown patch: "..tostring(op)) end
		end
	end)
end

function Session:Reset(path)
	if path==nil then return self:Restore(clone(self.Store.Template)) end
	local value=getAt(self.Store.Template,path)
	if value==nil then return false,"NO_TEMPLATE_VALUE" end
	return self:Set(path,clone(value))
end

function Session:Validate() 
	return self.Store:_validate(self.Data)
end

function Transaction:Compare(path,expected) 
	return deepEqual(self:Get(path),expected) 
end

function Store:_emit(event,...)
	for _,fn in ipairs(self.Events[event] or {}) do
		task.spawn(fn,...)
	end
end

function Store:_validate(data)
	local errors=Type.Check(data,self.Schema,"<root>")
	if self.Strict and #errors>0 then return false,table.concat(errors,"\n") end
	return #errors==0,#errors>0 and table.concat(errors,"\n") or nil
end

function Store:_replace(session,data,reason)
	if not session:IsActive() then return false,"SESSION_INACTIVE" end
	local old=session.Data
	session.Data=clone(data)
	local ok,err=self:_validate(session.Data)
	if not ok then session.Data=old; return false,err end
	session.MutationId+=1
	session.Dirty=true
	table.insert(session.Journal,{Id=session.MutationId,Operation=reason or "Replace",Path="",Before=clone(old),After=clone(session.Data),At=os.time()})
	return true
end

function Store:_txMutate(tx,op,path,value)
	if op=="Set" then setAt(tx.Data,path,clone(value))
	elseif op=="Delete" then deleteAt(tx.Data,path)
	elseif op=="Insert" then table.insert(getAt(tx.Data,path),clone(value))
	else error("Unknown operation") end
	return true
end

function Store:_key(player) return tostring(player.UserId) end

function Store:_request(fn)
	local last
	for attempt=1,self.RetryAttempts do
		local started=now()
		local ok,result=pcall(fn)
		if ok then return true,result end
		last=result
		if attempt<self.RetryAttempts and transient(result) then
			self.Metrics.Retries+=1
			task.wait(math.min(self.RetryMaxDelay,self.RetryBaseDelay*2^(attempt-1))*(0.75+math.random()*0.5))
		elseif attempt<self.RetryAttempts then
			task.wait(self.RetryBaseDelay)
		end
	end
	return false,last
end

function Store:GetSession(player)
	return self.Sessions[player]
end

function Store:GetSessionInfo(sessionOrPlayer)
	local s=typeof(sessionOrPlayer)=="table" and sessionOrPlayer or self:GetSession(sessionOrPlayer)
	if not s then return {Exists=false,Active=false} end
	return {
		Exists=true,Active=s.Active,Key=s.Key,Revision=s.Revision,Dirty=s.Dirty,
		MutationCount=s.MutationId,JournalSize=#s.Journal,Age=now()-s.LoadedAt,
		LastSaveAge=s.LastSaveAt>0 and now()-s.LastSaveAt or math.huge,
		LastHeartbeatAge=now()-s.LastHeartbeatAt,
	}
end


function Store:OnPlayerLoaded(fn)
	return self:On("PlayerLoaded",fn)
end

function Store:OnDataChanged(fn)
	return self:On("DataChanged",fn)
end

function Store:OnSaveFailed(fn) 
	return self:On("SaveFailed",fn)
end

function Store:OnSessionLost(fn)
	return self:On("SessionLost",fn)
end

function Store:OnSaveCompleted(fn)
	return self:On("SaveCompleted",fn) 
end

function Store:Publish(topic,payload)
	if not self.Config.CrossServer then return false,"CROSS_SERVER_DISABLED" end
	local ok,err=pcall(function()
		MessagingService:PublishAsync(self.Config.CrossServerPrefix and (self.Config.CrossServerPrefix..topic) or topic,payload)
	end)
	return ok,err
end

function Store:Subscribe(topic,fn)
	if not self.Config.CrossServer then return nil,"CROSS_SERVER_DISABLED" end
	local prefix=self.Config.CrossServerPrefix or ""
	local ok,sub=pcall(function()
		return MessagingService:SubscribeAsync(prefix..topic,function(message)
			fn(message.Data,message.Sent)
		end)
	end)
	if not ok then return nil,sub end
	return sub
end

function Store:_startLoops()
	task.spawn(function()
		while not self.Closed do
			task.wait(self.HeartbeatInterval)
			for _,s in pairs(self.Sessions) do
				if s.Active then
					local ok,err=self:_request(function()
						return self.DataStore:UpdateAsync(s.Key,function(old)
							old=old or {}
							local lock=old.__NDSLock
							if not lock or lock.JobId~=self.JobId then error("SESSION_OWNERSHIP_LOST") end
							old.__NDSLock.Heartbeat=os.time()
							return old
						end)
					end)
					if ok then
						s.LastHeartbeatAt=now(); self.Metrics.Heartbeats+=1
					else
						s.Active=false
						self.Sessions[s.Player]=nil
						self:_emit("SessionLost",s,err)
					end
				end
			end
		end
	end)
	task.spawn(function()
		while not self.Closed do
			task.wait(self.AutoSaveInterval)
			for _,s in pairs(self.Sessions) do
				if s.Active and s.Dirty then task.spawn(function() self:SaveAsync(s,"normal") end) end
			end
		end
	end)
end

local VERSION = "6.1.0"
local MAX_SAFE_INTEGER = 9007199254740991

function assertFiniteNumber(value, name)
	if typeof(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		error((name or "value") .. " must be a finite number", 2)
	end
	if math.abs(value) > MAX_SAFE_INTEGER then
		error((name or "value") .. " exceeds safe integer range", 2)
	end
	return value
end

function shallowClone(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

function countNodes(value, seen)
	if typeof(value) ~= "table" then
		return 1
	end
	seen = seen or {}
	if seen[value] then
		return 0
	end
	seen[value] = true
	local n = 1
	for k, v in pairs(value) do
		n += countNodes(k, seen)
		n += countNodes(v, seen)
	end
	return n
end

function estimateBytes(value)
	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(value)
	end)
	if ok and typeof(encoded) == "string" then
		return #encoded
	end
	return 0
end

function mergeDeep(baseValue, incoming, mode)
	if typeof(baseValue) ~= "table" or typeof(incoming) ~= "table" then
		return clone(incoming)
	end
	local result = clone(baseValue)
	for k, v in pairs(incoming) do
		if mode == "replace" then
			result[k] = clone(v)
		elseif typeof(v) == "table" and typeof(result[k]) == "table" then
			result[k] = mergeDeep(result[k], v, mode)
		else
			result[k] = clone(v)
		end
	end
	return result
end

function flatten(value, prefix, output)
	output = output or {}
	prefix = prefix or ""
	if typeof(value) ~= "table" then
		output[prefix] = clone(value)
		return output
	end
	local empty = true
	for k, v in pairs(value) do
		empty = false
		local nextPath = prefix == "" and tostring(k) or prefix .. "." .. tostring(k)
		flatten(v, nextPath, output)
	end
	if empty then
		output[prefix] = {}
	end
	return output
end

function normalizePath(path)
	local parts = pathParts(path)
	local result = table.create(#parts)
	for i, part in ipairs(parts) do
		if typeof(part) ~= "string" and typeof(part) ~= "number" then
			error("Path components must be strings or numbers", 3)
		end
		result[i] = part
	end
	return result
end

function hasCircularReference(value, stack, visited)
	if typeof(value) ~= "table" then
		return false
	end
	stack = stack or {}
	visited = visited or {}
	if stack[value] then
		return true
	end
	if visited[value] then
		return false
	end
	visited[value] = true
	stack[value] = true
	for k, v in pairs(value) do
		if hasCircularReference(k, stack, visited) or hasCircularReference(v, stack, visited) then
			return true
		end
	end
	stack[value] = nil
	return false
end

function validateSerializable(value)
	if hasCircularReference(value) then
		return false, "CIRCULAR_REFERENCE"
	end
	local ok, err = pcall(function()
		HttpService:JSONEncode(value)
	end)
	if not ok then
		return false, tostring(err)
	end
	return true
end

function deepFreeze(value, seen)
	if typeof(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return value
	end
	seen[value] = true
	for _, child in pairs(value) do
		deepFreeze(child, seen)
	end
	return value
end

function clamp(value, minimum, maximum)
	if value < minimum then
		return minimum
	end
	if value > maximum then
		return maximum
	end
	return value
end

function makeId(prefix)
	return string.format(
		"%s-%d-%d-%d",
		prefix or "NDS",
		os.time(),
		math.random(100000, 999999),
		math.random(100000, 999999)
	)
end

function isTransientErrorText(message)
	message = tostring(message):lower()
	return message:find("throttl") ~= nil
		or message:find("too many") ~= nil
		or message:find("429") ~= nil
		or message:find("timeout") ~= nil
		or message:find("timed out") ~= nil
		or message:find("500") ~= nil
		or message:find("502") ~= nil
		or message:find("503") ~= nil
		or message:find("504") ~= nil
end

function getServerIdentity()
	return {
		JobId = game.JobId,
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		ServerTime = os.time(),
	}
end

local SchemaEngine = {}

function SchemaEngine.Validate(value, schema, path, errors, options)
	path = path or "<root>"
	errors = errors or {}
	options = options or {}

	if schema == nil then
		return errors
	end

	local expected = schema.Type
	local actual = typeof(value)

	if expected and actual ~= expected then
		table.insert(errors, {
			Code = "TYPE",
			Path = path,
			Expected = expected,
			Actual = actual,
		})
		return errors
	end

	if schema.Required and value == nil then
		table.insert(errors, {
			Code = "REQUIRED",
			Path = path,
		})
		return errors
	end

	if value == nil then
		return errors
	end

	if actual == "number" then
		if schema.Finite ~= false and (value ~= value or value == math.huge or value == -math.huge) then
			table.insert(errors, {
				Code = "FINITE",
				Path = path,
			})
		end
		if schema.Min ~= nil and value < schema.Min then
			table.insert(errors, {
				Code = "MIN",
				Path = path,
				Value = value,
				Minimum = schema.Min,
			})
		end
		if schema.Max ~= nil and value > schema.Max then
			table.insert(errors, {
				Code = "MAX",
				Path = path,
				Value = value,
				Maximum = schema.Max,
			})
		end
		if schema.Integer and value % 1 ~= 0 then
			table.insert(errors, {
				Code = "INTEGER",
				Path = path,
			})
		end
	end

	if actual == "string" then
		if schema.MinLength and #value < schema.MinLength then
			table.insert(errors, {
				Code = "MIN_LENGTH",
				Path = path,
			})
		end
		if schema.MaxLength and #value > schema.MaxLength then
			table.insert(errors, {
				Code = "MAX_LENGTH",
				Path = path,
			})
		end
		if schema.Pattern then
			local found = string.find(value, schema.Pattern)
			if not found then
				table.insert(errors, {
					Code = "PATTERN",
					Path = path,
				})
			end
		end
	end

	if schema.Enum then
		local found = false
		for _, candidate in ipairs(schema.Enum) do
			if deepEqual(candidate, value) then
				found = true
				break
			end
		end
		if not found then
			table.insert(errors, {
				Code = "ENUM",
				Path = path,
			})
		end
	end

	if actual == "table" then
		if schema.ArrayOnly and not isArray(value) then
			table.insert(errors, {
				Code = "ARRAY",
				Path = path,
			})
		end

		if schema.MinItems and isArray(value) then
			local n = #value
			if n < schema.MinItems then
				table.insert(errors, {
					Code = "MIN_ITEMS",
					Path = path,
				})
			end
		end

		if schema.MaxItems and isArray(value) then
			local n = #value
			if n > schema.MaxItems then
				table.insert(errors, {
					Code = "MAX_ITEMS",
					Path = path,
				})
			end
		end

		if schema.ArrayOf and isArray(value) then
			for index, child in ipairs(value) do
				SchemaEngine.Validate(
					child,
					schema.ArrayOf,
					path .. "[" .. tostring(index) .. "]",
					errors,
					options
				)
			end
		end

		if schema.Children then
			for key, childSchema in pairs(schema.Children) do
				SchemaEngine.Validate(
					value[key],
					childSchema,
					path .. "." .. tostring(key),
					errors,
					options
				)
			end
		end

		if schema.AllowUnknown == false and schema.Children then
			for key in pairs(value) do
				if schema.Children[key] == nil then
					table.insert(errors, {
						Code = "UNKNOWN_FIELD",
						Path = path .. "." .. tostring(key),
					})
				end
			end
		end
	end

	if schema.Validator then
		local ok, result = pcall(schema.Validator, value, path)
		if not ok then
			table.insert(errors, {
				Code = "VALIDATOR_ERROR",
				Path = path,
				Message = tostring(result),
			})
		elseif result == false then
			table.insert(errors, {
				Code = "VALIDATOR",
				Path = path,
			})
		elseif typeof(result) == "string" then
			table.insert(errors, {
				Code = "VALIDATOR",
				Path = path,
				Message = result,
			})
		end
	end

	return errors
end

local MigrationEngine = {}

function MigrationEngine.Apply(data, currentVersion, migrations, context)
	local version = currentVersion or 1
	if typeof(migrations) ~= "table" then
		return data, version
	end

	local keys = {}
	for key in pairs(migrations) do
		if typeof(key) == "number" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)

	for _, targetVersion in ipairs(keys) do
		if targetVersion > version then
			local migration = migrations[targetVersion]
			if typeof(migration) == "function" then
				local ok, result = pcall(migration, data, context)
				if not ok then
					return nil, version, tostring(result)
				end
				if result ~= nil then
					data = result
				end
			elseif typeof(migration) == "table" and typeof(migration.Run) == "function" then
				local ok, result = pcall(migration.Run, data, context)
				if not ok then
					return nil, version, tostring(result)
				end
				if result ~= nil then
					data = result
				end
			end
			version = targetVersion
		end
	end

	return data, version
end

local CircuitBreaker = {}
CircuitBreaker.__index = CircuitBreaker

function CircuitBreaker.new(config)
	return setmetatable({
		Failures = 0,
		State = "Closed",
		OpenedAt = 0,
		Threshold = config.Threshold or 5,
		ResetAfter = config.ResetAfter or 30,
	}, CircuitBreaker)
end

function CircuitBreaker:Allow()
	if self.State == "Closed" then
		return true
	end
	if self.State == "Open" and now() - self.OpenedAt >= self.ResetAfter then
		self.State = "HalfOpen"
		return true
	end
	return self.State == "HalfOpen"
end

function CircuitBreaker:Success()
	self.Failures = 0
	self.State = "Closed"
	self.OpenedAt = 0
end

function CircuitBreaker:Failure()
	self.Failures += 1
	if self.Failures >= self.Threshold then
		self.State = "Open"
		self.OpenedAt = now()
	end
end

local PriorityQueue = {}
PriorityQueue.__index = PriorityQueue

function PriorityQueue.new()
	return setmetatable({
		Items = {},
		Sequence = 0,
	}, PriorityQueue)
end

function PriorityQueue:Push(item, priority)
	self.Sequence += 1
	table.insert(self.Items, {
		Item = item,
		Priority = priority or 0,
		Sequence = self.Sequence,
	})
end

function PriorityQueue:Pop()
	if #self.Items == 0 then
		return nil
	end

	local bestIndex = 1
	for index = 2, #self.Items do
		local current = self.Items[index]
		local best = self.Items[bestIndex]
		if current.Priority > best.Priority
			or (current.Priority == best.Priority and current.Sequence < best.Sequence) then
			bestIndex = index
		end
	end

	local entry = table.remove(self.Items, bestIndex)
	return entry and entry.Item
end

function PriorityQueue:Size()
	return #self.Items
end

local EventSignal = {}
EventSignal.__index = EventSignal

function EventSignal.new()
	return setmetatable({
		Handlers = {},
		OnceHandlers = {},
	}, EventSignal)
end

function EventSignal:Connect(callback)
	assert(typeof(callback) == "function", "Callback must be a function")
	local active = true
	table.insert(self.Handlers, callback)

	local connection = {}
	function connection:Disconnect()
		if not active then
			return
		end
		active = false
		for index, handler in ipairs(self.Handlers) do
			if handler == callback then
				table.remove(self.Handlers, index)
				break
			end
		end
	end

	return connection
end

function EventSignal:Once(callback)
	assert(typeof(callback) == "function", "Callback must be a function")
	table.insert(self.OnceHandlers, callback)
end

function EventSignal:Fire(...)
	local args = table.pack(...)
	for _, callback in ipairs(self.Handlers) do
		task.spawn(function()
			callback(table.unpack(args, 1, args.n))
		end)
	end
	local once = self.OnceHandlers
	self.OnceHandlers = {}
	for _, callback in ipairs(once) do
		task.spawn(function()
			callback(table.unpack(args, 1, args.n))
		end)
	end
end

function makeEventMap()
	local names = {
		"PlayerLoaded",
		"PlayerLoadFailed",
		"SessionOpened",
		"SessionLost",
		"SessionReleased",
		"DataChanged",
		"TransactionStarted",
		"TransactionCommitted",
		"TransactionRolledBack",
		"SaveQueued",
		"SaveStarted",
		"SaveCompleted",
		"SaveFailed",
		"MigrationStarted",
		"MigrationCompleted",
		"ValidationFailed",
		"SnapshotCreated",
		"SnapshotRestored",
		"CorruptionDetected",
		"CircuitOpened",
		"CircuitClosed",
		"ShutdownStarted",
		"ShutdownCompleted",
	}
	local map = {}
	for _, name in ipairs(names) do
		map[name] = EventSignal.new()
	end
	return map
end

function attach2State(store)
	store.Version = VERSION
	store.SchemaEngine = SchemaEngine
	store.MigrationEngine = MigrationEngine
	store.Circuit = CircuitBreaker.new(store.Config.CircuitBreaker or {})
	store.SaveQueue = PriorityQueue.new()
	store.Events2 = makeEventMap()
	store.Snapshots = {}
	store.Backups = {}
	store.MigrationHistory = {}
	store.ReadOnly = store.Config.ReadOnly == true
	store.Config.MaxDataNodes = store.Config.MaxDataNodes or 50000
	store.Config.MaxDataBytes = store.Config.MaxDataBytes or 4000000
	store.Config.MaxSnapshots = store.Config.MaxSnapshots or 10
	store.Config.BackupCount = store.Config.BackupCount or 3
	store.Config.SaveQueueInterval = store.Config.SaveQueueInterval or 0.5
	store.Config.MinimumSaveInterval = store.Config.MinimumSaveInterval or 2
	store.Config.MaxConcurrentSaves = store.Config.MaxConcurrentSaves or 2
	store._saveWorkers = 0
	store._queuedKeys = {}
	store._lastSaveByKey = {}
	store._shutdown = false
	store._version = VERSION
end

function emit2(store, name, ...)
	local signal = store.Events2 and store.Events2[name]
	if signal then
		signal:Fire(...)
	end
	local legacy = store.Events and store.Events[name]
	if legacy then
		for _, callback in ipairs(legacy) do
			task.spawn(callback, ...)
		end
	end
end

function validateLimits(store, data)
	local nodes = countNodes(data)
	if nodes > store.Config.MaxDataNodes then
		return false, "DATA_NODE_LIMIT"
	end
	local bytes = estimateBytes(data)
	if bytes > store.Config.MaxDataBytes then
		return false, "DATA_SIZE_LIMIT"
	end
	local serializable, err = validateSerializable(data)
	if not serializable then
		return false, err
	end
	return true
end

function buildEnvelope(store, session, data, release, lock)
	local encoded, digest = encode(data)
	local bytes = buffer.len(encoded)
	return {
		__NDSVersion = 61,
		__NDSFormat = 2,
		__NDSSchema = store.SchemaVersion,
		__NDSRevision = session.Revision + 1,
		__NDSChecksum = digest,
		__NDSBytes = bytes,
		__NDSNodes = countNodes(data),
		__NDSLock = release and nil or lock,
		__NDSSavedAt = os.time(),
		__NDSServer = getServerIdentity(),
		Data = data,
	}
end

function recordBackup(store, session, snapshot)
	local key = session.Key
	local bucket = store.Backups[key]
	if not bucket then
		bucket = {}
		store.Backups[key] = bucket
	end
	table.insert(bucket, 1, {
		Revision = session.Revision,
		Timestamp = os.time(),
		Data = clone(snapshot),
		Checksum = checksum(snapshot),
	})
	while #bucket > store.Config.BackupCount do
		table.remove(bucket)
	end
end

function Store:_validate2(data)
	local errors = SchemaEngine.Validate(data, self.Schema, "<root>", {})
	local limitOK, limitErr = validateLimits(self, data)
	if not limitOK then
		table.insert(errors, {
			Code = limitErr,
			Path = "<root>",
		})
	end

	if #errors > 0 then
		local messages = {}
		for _, entry in ipairs(errors) do
			table.insert(messages, string.format(
				"%s at %s%s",
				entry.Code,
				entry.Path,
				entry.Message and (": " .. entry.Message) or ""
				))
		end
		return false, table.concat(messages, "\n"), errors
	end

	return true
end

function Store:_emit2(name, ...)
	emit2(self, name, ...)
end

function Store:On2(eventName, callback)
	assert(self.Events2 and self.Events2[eventName], "Unknown V6.1 event: " .. tostring(eventName))
	return self.Events2[eventName]:Connect(callback)
end

function Store:On(eventName, callback)
	if self.Events2 and self.Events2[eventName] then
		return self.Events2[eventName]:Connect(callback)
	end
	self.Events[eventName] = self.Events[eventName] or {}
	table.insert(self.Events[eventName], callback)
	local active = true
	return {
		Disconnect = function()
			if not active then
				return
			end
			active = false
			local list = self.Events[eventName]
			if not list then
				return
			end
			for index, handler in ipairs(list) do
				if handler == callback then
					table.remove(list, index)
					break
				end
			end
		end,
	}
end

function Store:_enqueueSave2(session, priority, reason)
	if not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if self.ReadOnly then
		return false, "STORE_READ_ONLY"
	end

	local key = session.Key
	if not self._queuedKeys[key] then
		self._queuedKeys[key] = true
		self.SaveQueue:Push({
			Session = session,
			Reason = reason or "manual",
		}, priority or 0)
		self:_emit2("SaveQueued", session, reason)
	end
	return true
end

function Store:_saveDirect2(session, reason)
	if not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if self.ReadOnly then
		return false, "STORE_READ_ONLY"
	end

	local current = self._lastSaveByKey[session.Key]
	if current and now() - current < self.Config.MinimumSaveInterval and reason ~= "shutdown" then
		return true, "DEFERRED"
	end

	local valid, validationError = self:_validate2(session.Data)
	if not valid then
		self:_emit2("ValidationFailed", session, validationError)
		return false, validationError
	end

	if not self.Circuit:Allow() then
		return false, "CIRCUIT_OPEN"
	end

	local started = now()
	local snapshot = clone(session.Data)
	local expectedRevision = session.Revision
	local lock = {
		JobId = self.JobId,
		Heartbeat = os.time(),
		PlayerId = session.Player.UserId,
		SessionId = session.SessionId,
	}

	self:_emit2("SaveStarted", session, reason)

	local ok, result = self:_request(function()
		return self.DataStore:UpdateAsync(session.Key, function(old)
			old = old or {}
			local existingLock = old.__NDSLock

			if existingLock and existingLock.JobId ~= self.JobId then
				error("SESSION_OWNERSHIP_LOST")
			end

			local envelope = buildEnvelope(self, session, snapshot, false, lock)
			envelope.__NDSRevision = expectedRevision + 1
			return envelope
		end)
	end)

	if not ok then
		self.Circuit:Failure()
		self:_emit2("SaveFailed", session, result)
		if self.Circuit.State == "Open" then
			self:_emit2("CircuitOpened", session, result)
		end
		return false, result
	end

	if self.Circuit.State ~= "Closed" then
		self.Circuit:Success()
		self:_emit2("CircuitClosed", session)
	end

	recordBackup(self, session, snapshot)

	session.Revision += 1
	session.LastSaveAt = now()
	session.Dirty = false
	session.LastPersistedSnapshot = clone(snapshot)
	session.LastPersistedChecksum = checksum(snapshot)
	self._lastSaveByKey[session.Key] = now()

	self.Metrics.Saves += 1
	self.Metrics.SaveTime += now() - started

	self:_emit2("SaveCompleted", session, result)
	return true, result
end

function Store:QueueSave(session, priority, reason)
	return self:_enqueueSave2(session, priority, reason)
end

function Store:SaveAsync(session, priority)
	local queued, err = self:_enqueueSave2(session, priority or 50, "manual")
	if not queued then
		return false, err
	end

	if self._saveWorkers < self.Config.MaxConcurrentSaves then
		self:_drainSaveQueue()
	end

	local deadline = now() + (self.Config.SaveTimeout or 30)
	while now() < deadline do
		if not session:IsActive() then
			return false, "SESSION_INACTIVE"
		end
		if not session.Dirty then
			return true
		end
		task.wait(0.05)
	end

	return false, "SAVE_TIMEOUT"
end

function Store:_drainSaveQueue()
	if self._saveWorkers >= self.Config.MaxConcurrentSaves then
		return
	end

	local job = self.SaveQueue:Pop()
	if not job then
		return
	end

	local session = job.Session
	self._queuedKeys[session.Key] = nil
	if not session:IsActive() then
		self:_drainSaveQueue()
		return
	end

	self._saveWorkers += 1
	task.spawn(function()
		local ok, err = self:_saveDirect2(session, job.Reason)
		if not ok and err ~= "DEFERRED" then
			session.LastSaveError = err
		end
		self._saveWorkers -= 1
		self:_drainSaveQueue()
	end)
end

function Store:_start2Workers()
	if self._2WorkersStarted then
		return
	end
	self._2WorkersStarted = true

	task.spawn(function()
		while not self._shutdown do
			task.wait(self.Config.SaveQueueInterval)
			for _ = 1, self.Config.MaxConcurrentSaves do
				if self._saveWorkers >= self.Config.MaxConcurrentSaves then
					break
				end
				self:_drainSaveQueue()
			end
		end
	end)
end

function Store:CreateSnapshot(session, label)
	assert(session and session:IsActive(), "Active session required")
	local snapshot = {
		Id = makeId("SNAP"),
		Label = label or "Snapshot",
		CreatedAt = os.time(),
		Revision = session.Revision,
		Checksum = checksum(session.Data),
		Data = clone(session.Data),
	}
	local list = self.Snapshots[session.Key]
	if not list then
		list = {}
		self.Snapshots[session.Key] = list
	end
	table.insert(list, 1, snapshot)
	while #list > self.Config.MaxSnapshots do
		table.remove(list)
	end
	self:_emit2("SnapshotCreated", session, snapshot)
	return snapshot
end

function Store:GetSnapshots(session)
	local list = self.Snapshots[session.Key] or {}
	return clone(list)
end

function Store:RestoreSnapshot(session, snapshotId)
	local list = self.Snapshots[session.Key] or {}
	for _, snapshot in ipairs(list) do
		if snapshot.Id == snapshotId then
			local ok, err = session:Restore(snapshot.Data)
			if not ok then
				return false, err
			end
			self:_emit2("SnapshotRestored", session, snapshot)
			return true
		end
	end
	return false, "SNAPSHOT_NOT_FOUND"
end

function Store:GetBackupHistory(session)
	return clone(self.Backups[session.Key] or {})
end

function Store:RestoreBackup(session, revision)
	for _, backup in ipairs(self.Backups[session.Key] or {}) do
		if backup.Revision == revision then
			return session:Restore(backup.Data)
		end
	end
	return false, "BACKUP_NOT_FOUND"
end

function Store:GetDiff(session, other)
	return diff(session.Data, other)
end

function Store:Merge(session, incoming, mode)
	if not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	local merged = mergeDeep(session.Data, incoming, mode or "deep")
	return session:Restore(merged)
end

function Store:ExportSession(session)
	local data = clone(session.Data)
	local encoded, digest = encode(data)
	return {
		Version = VERSION,
		SchemaVersion = self.SchemaVersion,
		Revision = session.Revision,
		Checksum = digest,
		Bytes = buffer.len(encoded),
		Data = data,
	}
end

function Store:ImportIntoSession(session, payload, options)
	options = options or {}
	if typeof(payload) == "table" and payload.Data then
		payload = payload.Data
	end
	if typeof(payload) ~= "table" then
		return false, "INVALID_IMPORT"
	end
	if options.Merge then
		return self:Merge(session, payload, options.Mode or "deep")
	end
	return session:Restore(payload)
end

function Store:GetDataStats(session)
	return {
		Nodes = countNodes(session.Data),
		EstimatedBytes = estimateBytes(session.Data),
		Checksum = checksum(session.Data),
		Revision = session.Revision,
		MutationCount = session.MutationId,
		JournalEntries = #session.Journal,
		Dirty = session.Dirty,
	}
end

function Store:SetReadOnly(value)
	self.ReadOnly = value == true
	return self.ReadOnly
end

function Store:IsReadOnly()
	return self.ReadOnly
end

function Store:GetVersion()
	return self.Version
end

function Store:GetQueueSize()
	return self.SaveQueue and self.SaveQueue:Size() or 0
end

function Store:GetCircuitState()
	return self.Circuit.State
end

function Store:ValidateAllSessions()
	local results = {}
	for _, session in pairs(self.Sessions) do
		local ok, err = self:_validate2(session.Data)
		results[session.Key] = {
			OK = ok,
			Error = err,
		}
	end
	return results
end

function Store:RunMaintenance()
	local report = {
		StartedAt = os.time(),
		ActiveSessions = 0,
		DirtySessions = 0,
		InvalidSessions = 0,
		QueuedSaves = self:GetQueueSize(),
	}

	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			report.ActiveSessions += 1
			if session.Dirty then
				report.DirtySessions += 1
			end
			local valid = self:_validate2(session.Data)
			if not valid then
				report.InvalidSessions += 1
			end
		end
	end

	report.CompletedAt = os.time()
	return report
end

function Store:ApplyMigration(session)
	local migrations = self.Config.Migrations
	if typeof(migrations) ~= "table" then
		return true
	end

	local targetVersion = self.SchemaVersion
	local currentVersion = session.SchemaVersion or 1
	if currentVersion >= targetVersion then
		return true
	end

	self:_emit2("MigrationStarted", session, currentVersion, targetVersion)

	local migrated, version, err = MigrationEngine.Apply(
		session.Data,
		currentVersion,
		migrations,
		{
			Store = self,
			Session = session,
			Player = session.Player,
		}
	)

	if not migrated then
		return false, err
	end

	local valid, validationError = self:_validate2(migrated)
	if not valid then
		return false, validationError
	end

	session.Data = migrated
	session.SchemaVersion = version
	session.Dirty = true
	table.insert(self.MigrationHistory, {
		Key = session.Key,
		From = currentVersion,
		To = version,
		Timestamp = os.time(),
	})

	self:_emit2("MigrationCompleted", session, currentVersion, version)
	return true
end

function Session:Set(path, value)
	if self.Store.ReadOnly then
		return false, "STORE_READ_ONLY"
	end
	local serializable, err = validateSerializable(value)
	if not serializable then
		return false, err
	end
	self._beforeMutation = clone(self.Data)
	return self.Store:_mutate(self, "Set", normalizePath(path), value)
end

function Session:Delete(path)
	if self.Store.ReadOnly then
		return false, "STORE_READ_ONLY"
	end
	self._beforeMutation = clone(self.Data)
	return self.Store:_mutate(self, "Delete", normalizePath(path), nil)
end

function Session:Increment(path, amount)
	amount = amount or 1
	assertFiniteNumber(amount, "amount")
	local current = self:Get(path)
	if typeof(current) ~= "number" then
		return false, "NOT_NUMBER"
	end
	assertFiniteNumber(current, "stored number")
	return self:Set(path, current + amount)
end

function Session:IncrementClamped(path, amount, minimum, maximum)
	local current = self:Get(path)
	if typeof(current) ~= "number" then
		return false, "NOT_NUMBER"
	end
	local nextValue = clamp(current + (amount or 1), minimum, maximum)
	return self:Set(path, nextValue)
end

function Session:Push(path, ...)
	local values = table.pack(...)
	local list = self:Get(path)
	if typeof(list) ~= "table" then
		return false, "NOT_TABLE"
	end
	return self:Transaction(function(tx)
		for index = 1, values.n do
			tx:Insert(path, values[index])
		end
	end)
end

function Session:Pop(path)
	local list = self:Get(path)
	if typeof(list) ~= "table" or #list == 0 then
		return nil, "EMPTY"
	end
	local value = list[#list]
	local ok, err = self:Delete({pathParts(path), #list})
	if not ok then
		return nil, err
	end
	return value
end

function Session:Has(path)
	return self:Get(path) ~= nil
end

function Session:Exists(path)
	return self:Has(path)
end

function Session:Clone()
	return clone(self.Data)
end

function Session:FreezeClone()
	return deepFreeze(clone(self.Data))
end

function Session:GetDataSize()
	return estimateBytes(self.Data)
end

function Session:GetNodeCount()
	return countNodes(self.Data)
end

function Session:GetChecksum()
	return checksum(self.Data)
end

function Session:GetLastSaveError()
	return self.LastSaveError
end

function Session:GetRevision()
	return self.Revision
end

function Session:GetSchemaVersion()
	return self.SchemaVersion or self.Store.SchemaVersion
end

function Session:IsDirty()
	return self.Dirty
end

function Session:GetSessionId()
	return self.SessionId
end

function Session:GetPlayer()
	return self.Player
end

function Session:GetStore()
	return self.Store
end

function Session:QueueSave(priority, reason)
	return self.Store:QueueSave(self, priority, reason)
end

function Session:CreateSnapshot(label)
	return self.Store:CreateSnapshot(self, label)
end

function Session:GetSnapshots()
	return self.Store:GetSnapshots(self)
end

function Session:GetBackups()
	return self.Store:GetBackupHistory(self)
end

function Session:Export()
	return self.Store:ExportSession(self)
end

function Session:Import(payload, options)
	return self.Store:ImportIntoSession(self, payload, options)
end

function Session:GetStats()
	return self.Store:GetDataStats(self)
end

function Session:Merge(data, mode)
	return self.Store:Merge(self, data, mode)
end

function Session:ValidateDetailed()
	return self.Store:_validate2(self.Data)
end

function Session:ReadOnly()
	return self.Store.ReadOnly
end

function Session:Touch()
	self.Dirty = true
	self.LastTouchedAt = now()
	return true
end

function Session:ReleaseWithoutSave()
	return self.Store:ReleaseAsync(self, false)
end

function Transaction:Get(path)
	return getAt(self.Data, normalizePath(path))
end

function Transaction:Set(path, value)
	assert(validateSerializable(value), "Value is not serializable")
	return self.Store:_txMutate(self, "Set", normalizePath(path), value)
end

function Transaction:Delete(path)
	return self.Store:_txMutate(self, "Delete", normalizePath(path), nil)
end

function Transaction:Increment(path, amount)
	local current = self:Get(path)
	if typeof(current) ~= "number" then
		error("Transaction Increment requires a number", 2)
	end
	return self:Set(path, current + (amount or 1))
end

function Transaction:IncrementClamped(path, amount, minimum, maximum)
	local current = self:Get(path)
	if typeof(current) ~= "number" then
		error("Transaction IncrementClamped requires a number", 2)
	end
	return self:Set(path, clamp(current + (amount or 1), minimum, maximum))
end

function Transaction:Insert(path, value)
	local list = self:Get(path)
	if typeof(list) ~= "table" then
		error("Transaction Insert requires a table", 2)
	end
	return self.Store:_txMutate(self, "Insert", normalizePath(path), value)
end

function Transaction:RemoveAt(path, index)
	local list = self:Get(path)
	if typeof(list) ~= "table" then
		error("Transaction RemoveAt requires a table", 2)
	end
	if typeof(index) ~= "number" or index < 1 or index > #list then
		return false, "INDEX_OUT_OF_RANGE"
	end
	local copy = clone(list)
	table.remove(copy, index)
	return self:Set(path, copy)
end

function Transaction:Push(path, ...)
	local values = table.pack(...)
	for index = 1, values.n do
		self:Insert(path, values[index])
	end
	return true
end

function Transaction:CompareAndSet(path, expected, value)
	if not deepEqual(self:Get(path), expected) then
		return false, "COMPARE_FAILED"
	end
	return self:Set(path, value)
end

function Transaction:Require(path, predicateOrValue)
	local value = self:Get(path)
	if typeof(predicateOrValue) == "function" then
		local ok, result = pcall(predicateOrValue, value)
		if not ok then
			error(result, 2)
		end
		if not result then
			error("TRANSACTION_PRECONDITION_FAILED", 2)
		end
	elseif not deepEqual(value, predicateOrValue) then
		error("TRANSACTION_PRECONDITION_FAILED", 2)
	end
	return value
end

function Transaction:Map(path, callback)
	local list = self:Get(path)
	if typeof(list) ~= "table" then
		error("Transaction Map requires a table", 2)
	end
	local output = {}
	for index, value in pairs(list) do
		output[index] = callback(value, index)
	end
	return self:Set(path, output)
end

function Transaction:Filter(path, callback)
	local list = self:Get(path)
	if typeof(list) ~= "table" then
		error("Transaction Filter requires a table", 2)
	end
	local output = {}
	for index, value in pairs(list) do
		if callback(value, index) then
			table.insert(output, clone(value))
		end
	end
	return self:Set(path, output)
end

function Transaction:Merge(path, incoming, mode)
	local current = self:Get(path)
	return self:Set(path, mergeDeep(current, incoming, mode or "deep"))
end

function Transaction:Savepoint()
	return clone(self.Data)
end

function Transaction:RollbackTo(snapshot)
	assert(typeof(snapshot) == "table", "Snapshot must be a table")
	self.Data = clone(snapshot)
	return true
end

function Transaction:Diff()
	return diff(self.Session.Data, self.Data)
end

function Transaction:Validate()
	return self.Store:_validate2(self.Data)
end

function Store:_transaction(session, callback)
	if not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if self.ReadOnly then
		return false, "STORE_READ_ONLY"
	end

	self:_emit2("TransactionStarted", session)

	local transaction = setmetatable({
		Store = self,
		Session = session,
		Data = clone(session.Data),
		Id = makeId("TX"),
		StartedAt = now(),
	}, Transaction)

	local ok, result = pcall(callback, transaction)
	if not ok then
		self.Metrics.Rollbacks += 1
		self:_emit2("TransactionRolledBack", session, transaction.Id, result)
		return false, result
	end

	local valid, validationError = self:_validate2(transaction.Data)
	if not valid then
		self.Metrics.Rollbacks += 1
		self:_emit2("TransactionRolledBack", session, transaction.Id, validationError)
		return false, validationError
	end

	local before = session.Data
	local changes = diff(before, transaction.Data)

	if #changes == 0 then
		self:_emit2("TransactionCommitted", session, transaction.Id, changes, true)
		return true, result
	end

	session.Data = transaction.Data
	session.MutationId += 1
	session.Dirty = true
	session.LastTouchedAt = now()

	table.insert(session.Journal, {
		Id = session.MutationId,
		TransactionId = transaction.Id,
		Operation = "Transaction",
		Path = "",
		Before = clone(before),
		After = clone(session.Data),
		Changes = changes,
		At = os.time(),
	})

	while #session.Journal > self.MaxJournalEntries do
		table.remove(session.Journal, 1)
	end

	self.Metrics.Transactions += 1
	self.Metrics.Mutations += 1

	self:_emit2("TransactionCommitted", session, transaction.Id, changes, false)
	self:_emit2("DataChanged", session, "", before, session.Data)

	return true, result
end

function Store:_mutate(session, operation, path, value)
	if not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end
	if self.ReadOnly then
		return false, "STORE_READ_ONLY"
	end

	path = normalizePath(path)
	local beforeData = clone(session.Data)
	local before = clone(getAt(session.Data, path))

	if operation == "Set" then
		setAt(session.Data, path, clone(value))
	elseif operation == "Delete" then
		deleteAt(session.Data, path)
	elseif operation == "Insert" then
		local list = getAt(session.Data, path)
		if typeof(list) ~= "table" then
			session.Data = beforeData
			return false, "NOT_TABLE"
		end
		table.insert(list, clone(value))
	else
		session.Data = beforeData
		return false, "UNKNOWN_OPERATION"
	end

	local valid, validationError = self:_validate2(session.Data)
	if not valid then
		session.Data = beforeData
		self:_emit2("ValidationFailed", session, validationError, path)
		return false, validationError
	end

	session.MutationId += 1
	session.Dirty = true
	session.LastTouchedAt = now()

	local after = clone(getAt(session.Data, path))
	local entry = {
		Id = session.MutationId,
		Operation = operation,
		Path = pathString(path),
		Before = before,
		After = after,
		At = os.time(),
	}

	table.insert(session.Journal, entry)
	while #session.Journal > self.MaxJournalEntries do
		table.remove(session.Journal, 1)
	end

	self.Metrics.Mutations += 1
	self:_emit2("DataChanged", session, path, before, after, entry)

	return true
end

function Store:GetMetrics()
	local metrics = clone(self.Metrics)
	metrics.Version = self.Version
	metrics.ActiveSessions = 0
	metrics.DirtySessions = 0
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			metrics.ActiveSessions += 1
			if session.Dirty then
				metrics.DirtySessions += 1
			end
		end
	end
	metrics.SaveQueue = self:GetQueueSize()
	metrics.CircuitState = self:GetCircuitState()
	if metrics.Loads > 0 then
		metrics.AverageLoadTime = metrics.LoadTime / metrics.Loads
	end
	if metrics.Saves > 0 then
		metrics.AverageSaveTime = metrics.SaveTime / metrics.Saves
	end
	return metrics
end

function Store:GetHealth()
	local metrics = self:GetMetrics()
	local budget = DataStoreService:GetRequestBudgetForRequestType(
		Enum.DataStoreRequestType.UpdateAsync
	)
	return {
		Healthy = self.Circuit.State ~= "Open",
		Version = self.Version,
		JobId = self.JobId,
		ActiveSessions = metrics.ActiveSessions,
		DirtySessions = metrics.DirtySessions,
		QueueSize = metrics.SaveQueue,
		UpdateBudget = budget,
		Circuit = self.Circuit.State,
		Metrics = metrics,
	}
end

function Store:FlushAsync(timeout)
	timeout = timeout or 30
	local deadline = now() + timeout

	for _, session in pairs(self.Sessions) do
		if session:IsActive() and session.Dirty then
			self:QueueSave(session, 100, "flush")
		end
	end

	while now() < deadline do
		local dirty = false
		for _, session in pairs(self.Sessions) do
			if session:IsActive() and session.Dirty then
				dirty = true
				break
			end
		end
		if not dirty and self:GetQueueSize() == 0 and self._saveWorkers == 0 then
			return true
		end
		task.wait(0.1)
	end

	return false, "FLUSH_TIMEOUT"
end

function Store:Close()
	if self._shutdown then
		return true
	end

	self._shutdown = true
	self.Closed = true
	self:_emit2("ShutdownStarted", self)

	local flushOK, flushErr = self:FlushAsync(self.Config.ShutdownTimeout or 30)

	local sessions = {}
	for _, session in pairs(self.Sessions) do
		table.insert(sessions, session)
	end

	for _, session in ipairs(sessions) do
		if session:IsActive() then
			self:ReleaseAsync(session, false)
		end
	end

	self:_emit2("ShutdownCompleted", self, flushOK, flushErr)
	return flushOK, flushErr
end

function Store:Initialize2()
	if self._2Initialized then
		return self
	end

	attach2State(self)
	self:_start2Workers()

	if self.Config.Migrations then
		self.SchemaVersion = self.Config.SchemaVersion
			or (self.Config.DataTemplate and self.Config.DataTemplate.Version)
			or self.SchemaVersion
	end

	return self
end

function Store:GetServerInfo()
	return getServerIdentity()
end

function Store:CreateKey(userId)
	return self:_key({
		UserId = userId,
	})
end

function Store:GetStoreInfo()
	return {
		Name = self.Name,
		Version = self.Version,
		SchemaVersion = self.SchemaVersion,
		Closed = self.Closed,
		ReadOnly = self.ReadOnly,
		ActiveSessions = self:GetMetrics().ActiveSessions,
		QueueSize = self:GetQueueSize(),
		Circuit = self:GetCircuitState(),
	}
end

Store.GetHealthReport = Store.GetHealth
Store.GetStatistics = Store.GetMetrics
Store.GetStoreStats = Store.GetStoreInfo
Store.Flush = Store.FlushAsync
Store.Queue = Store.QueueSave

local OriginalNew = Store.new

function Store.new(config)
	local store = OriginalNew(config)
	store:Initialize2()
	return store
end

local OriginalOpenPlayerAsync = Store.OpenPlayerAsync

function Store:OpenPlayerAsync(player)
	local session, err = OriginalOpenPlayerAsync(self, player)
	if not session then
		return nil, err
	end

	session.SessionId = makeId("SESSION")
	session.SchemaVersion = self.SchemaVersion
	session.LastPersistedSnapshot = clone(session.Data)
	session.LastPersistedChecksum = checksum(session.Data)
	session.LastTouchedAt = now()
	session.LastSaveError = nil

	local migrationOK, migrationError = self:ApplyMigration(session)
	if not migrationOK then
		self:_emit2("PlayerLoadFailed", player, migrationError)
		self.Sessions[player] = nil
		session.Active = false
		return nil, "MIGRATION_FAILED:" .. tostring(migrationError)
	end

	local valid, validationError = self:_validate2(session.Data)
	if not valid then
		self:_emit2("CorruptionDetected", session, validationError)
		self.Sessions[player] = nil
		session.Active = false
		return nil, "DATA_CORRUPTION:" .. tostring(validationError)
	end

	self:_emit2("SessionOpened", session)
	return session
end

local OriginalReleaseAsync = Store.ReleaseAsync

function Store:ReleaseAsync(session, save)
	if not session or not session:IsActive() then
		return false, "SESSION_INACTIVE"
	end

	if save ~= false and session.Dirty then
		local ok, err = self:_saveDirect2(session, "release")
		if not ok then
			return false, err
		end
	end

	local ok, result = self:_request(function()
		return self.DataStore:UpdateAsync(session.Key, function(old)
			old = old or {}
			local lock = old.__NDSLock

			if lock and lock.JobId ~= self.JobId then
				error("SESSION_OWNERSHIP_LOST")
			end

			old.__NDSLock = nil
			old.__NDSReleasedAt = os.time()
			old.__NDSReleasedBy = getServerIdentity()
			return old
		end)
	end)

	if not ok then
		self:_emit2("SaveFailed", session, result)
		return false, result
	end

	session.Active = false
	self.Sessions[session.Player] = nil

	self:_emit2("SessionReleased", session)
	self:_emit2("PlayerRemoving", session.Player, session)

	return true
end

function Session:Get(path)
	return getAt(self.Data, normalizePath(path))
end

function Session:SetIf(path, predicate, value)
	local current = self:Get(path)
	local ok, result = pcall(predicate, current)
	if not ok then
		return false, result
	end
	if not result then
		return false, "PREDICATE_FAILED"
	end
	return self:Set(path, value)
end

function Session:CompareAndSet(path, expected, value)
	return self:Transaction(function(tx)
		local ok, err = tx:CompareAndSet(path, expected, value)
		if not ok then
			error(err)
		end
	end)
end

function Session:Mutate(callback)
	return self:Transaction(function(tx)
		return callback(tx)
	end)
end

function Session:Require(path, expectedOrPredicate)
	local value = self:Get(path)
	if typeof(expectedOrPredicate) == "function" then
		local ok, result = pcall(expectedOrPredicate, value)
		if not ok then
			return false, result
		end
		return result == true, result == true and nil or "PREDICATE_FAILED"
	end
	return deepEqual(value, expectedOrPredicate), deepEqual(value, expectedOrPredicate) and nil or "VALUE_MISMATCH"
end

function Session:GetFlattened()
	return flatten(self.Data)
end

function Session:GetPathValues()
	return self:GetFlattened()
end

function Session:RestoreTemplate(path)
	if path == nil then
		return self:Restore(clone(self.Store.Template))
	end
	local templateValue = getAt(self.Store.Template, path)
	if templateValue == nil then
		return false, "TEMPLATE_PATH_NOT_FOUND"
	end
	return self:Set(path, clone(templateValue))
end

function Session:GetBackup(revision)
	for _, backup in ipairs(self.Store.Backups[self.Key] or {}) do
		if backup.Revision == revision then
			return clone(backup)
		end
	end
	return nil
end

function Session:RollbackToRevision(revision)
	local backup = self:GetBackup(revision)
	if not backup then
		return false, "BACKUP_NOT_FOUND"
	end
	return self:Restore(backup.Data)
end

function Session:GetJournalRange(startIndex, endIndex)
	startIndex = startIndex or 1
	endIndex = endIndex or #self.Journal
	local result = {}
	for index = startIndex, math.min(endIndex, #self.Journal) do
		table.insert(result, clone(self.Journal[index]))
	end
	return result
end

function Session:ClearJournal()
	self.Journal = {}
	return true
end

function Session:QueueHighPrioritySave(reason)
	return self:QueueSave(100, reason or "high")
end

function Session:QueueLowPrioritySave(reason)
	return self:QueueSave(10, reason or "low")
end

function Session:GetStatus()
	local info = self.Store:GetSessionInfo(self)
	info.SessionId = self.SessionId
	info.SchemaVersion = self.SchemaVersion
	info.LastSaveError = self.LastSaveError
	info.LastTouchedAge = self.LastTouchedAt and now() - self.LastTouchedAt or nil
	info.DataBytes = estimateBytes(self.Data)
	info.DataNodes = countNodes(self.Data)
	info.Checksum = checksum(self.Data)
	return info
end

function Store:AttachPlayerLifecycle(loadFailureMessage)
	if self._lifecycleAttached then
		return false, "LIFECYCLE_ALREADY_ATTACHED"
	end

	self._lifecycleAttached = true

	Players.PlayerAdded:Connect(function(player)
		local session, err = self:OpenPlayerAsync(player)
		if not session then
			self:_emit2("PlayerLoadFailed", player, err)
			if player.Parent then
				player:Kick(loadFailureMessage or "Your data could not be loaded. Please rejoin.")
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local session = self:GetSession(player)
		if session then
			local ok, err = self:ReleaseAsync(session, true)
			if not ok then
				warn("[NexusDataStore] Release failed:", player.Name, err)
			end
		end
	end)

	return true
end

function Store:BindToClose()
	if self._boundToClose then
		return false, "ALREADY_BOUND"
	end
	self._boundToClose = true
	game:BindToClose(function()
		self:Close()
	end)
	return true
end

function Store:DumpDiagnostics()
	local health = self:GetHealth()
	local info = self:GetStoreInfo()
	return {
		Store = info,
		Health = health,
		Server = self:GetServerInfo(),
		Maintenance = self:RunMaintenance(),
		Sessions = self:ValidateAllSessions(),
	}
end

function Store:AssertHealthy()
	local health = self:GetHealth()
	if not health.Healthy then
		return false, "STORE_UNHEALTHY"
	end
	if health.UpdateBudget <= 0 then
		return false, "NO_UPDATE_BUDGET"
	end
	return true
end

function Store:GetSchema()
	return clone(self.Schema)
end

function Store:GetTemplate()
	return clone(self.Template)
end

function Store:SetSchemaVersion(version)
	assert(typeof(version) == "number" and version >= 1, "Schema version must be a positive number")
	self.SchemaVersion = version
	return version
end

function Store:GetMigrationHistory()
	return clone(self.MigrationHistory)
end

function Store:GetSessionById(sessionId)
	for _, session in pairs(self.Sessions) do
		if session.SessionId == sessionId and session:IsActive() then
			return session
		end
	end
	return nil
end

function Store:GetActiveSessions()
	local result = {}
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			table.insert(result, session)
		end
	end
	return result
end

function Store:ForEachSession(callback)
	assert(typeof(callback) == "function", "Callback must be a function")
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			callback(session)
		end
	end
end

function Session:GetPlayerUserId()
	return self.Player.UserId
end

function Session:GetKey()
	return self.Key
end

function Session:GetAge()
	return math.max(0, now() - (self.OpenedAt or now()))
end

function Session:GetTimeSinceSave()
	if not self.LastSaveAt then
		return math.huge
	end
	return math.max(0, now() - self.LastSaveAt)
end

function Session:GetMutationCount()
	return self.MutationId
end

function Session:GetJournal()
	return clone(self.Journal)
end

function Session:ClearDirty()
	self.Dirty = false
	return true
end

function Session:MarkDirty()
	self.Dirty = true
	self.LastTouchedAt = now()
	return true
end

function Session:Save(priority)
	return self.Store:SaveAsync(self, priority or 75)
end

function Session:Flush(timeout)
	return self.Store:FlushAsync(timeout)
end

function Session:Health()
	return self.Store:GetHealth()
end

function Session:DiffFromPersisted()
	return diff(self.LastPersistedSnapshot or {}, self.Data)
end

function Session:IsHealthy()
	local ok = self:ValidateDetailed()
	return ok == true
end

function Session:Replace(data)
	return self:Restore(data)
end

function Session:Update(callback)
	assert(typeof(callback) == "function", "Callback must be a function")
	return self:Transaction(function(tx)
		return callback(tx, self.Data)
	end)
end

function Transaction:GetSession()
	return self.Session
end

function Transaction:GetId()
	return self.Id
end

function Transaction:GetAge()
	return math.max(0, now() - self.StartedAt)
end

function Transaction:DeleteIf(path, predicate)
	local value = self:Get(path)
	if not predicate(value) then
		return false, "PREDICATE_FAILED"
	end
	return self:Delete(path)
end

function Transaction:SetIf(path, predicate, value)
	local current = self:Get(path)
	if not predicate(current) then
		return false, "PREDICATE_FAILED"
	end
	return self:Set(path, value)
end

function Transaction:Touch()
	return true
end

function Transaction:Count(path)
	local value = self:Get(path)
	if typeof(value) ~= "table" then
		return 0
	end
	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

function Transaction:Contains(path, expected)
	local value = self:Get(path)
	if typeof(value) ~= "table" then
		return false
	end
	for _, child in pairs(value) do
		if deepEqual(child, expected) then
			return true
		end
	end
	return false
end

function Store:SaveAllAsync(timeout)
	for _, session in pairs(self.Sessions) do
		if session:IsActive() and session.Dirty then
			self:QueueSave(session, 100, "save-all")
		end
	end
	return self:FlushAsync(timeout)
end

function Store:CountSessions()
	local count = 0
	for _, session in pairs(self.Sessions) do
		if session:IsActive() then
			count += 1
		end
	end
	return count
end

function Store:HasSession(player)
	local session = self:GetSession(player)
	return session ~= nil and session:IsActive()
end

function Store:WaitForSession(player, timeout)
	local deadline = now() + (timeout or 30)
	repeat
		local session = self:GetSession(player)
		if session and session:IsActive() then
			return session
		end
		task.wait()
	until now() >= deadline
	return nil, "SESSION_TIMEOUT"
end

return Store
