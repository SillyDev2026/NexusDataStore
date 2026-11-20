--!strict
--!native
--!optimize 2

-- Optional receipt adapter for NexusDataStore v9.
-- A grant and its receipt ID must enter the same persistent profile snapshot.
-- The callback is non-yielding, server-owned, and must have no external side effects.
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local NexusReceipts = {}
NexusReceipts.__index = NexusReceipts

export type Grant = (draft: {[string]: any}, receipt: any) -> ()
export type Grants = {[number]: Grant}

function NexusReceipts.new(store: any, grants: Grants, receiptPath: string?): any
	assert(typeof(store) == "table" and typeof(store.GetSession) == "function", "Valid NexusDataStore required")
	assert(typeof(grants) == "table", "Product grants table required")
	local field = receiptPath or "ProcessedReceipts"
	assert(typeof(field) == "string" and #field > 0 and #field <= 64, "Invalid receipt field")
	for productId, grant in pairs(grants) do
		assert(typeof(productId) == "number" and productId > 0 and productId % 1 == 0, "Invalid ProductId")
		assert(typeof(grant) == "function", "Grant handler must be a function")
	end
	return setmetatable({Store = store, Grants = grants, Field = field}, NexusReceipts)
end

-- Return this method from MarketplaceService.ProcessReceipt. Do not chain
-- competing receipt handlers; Roblox supports only one ProcessReceipt callback.
function NexusReceipts:ProcessReceipt(receipt: any): Enum.ProductPurchaseDecision
	local retry = Enum.ProductPurchaseDecision.NotProcessedYet
	if typeof(receipt) ~= "table" then return retry end
	local purchaseId = receipt.PurchaseId
	if typeof(purchaseId) ~= "string" or #purchaseId == 0 or #purchaseId > 128 then return retry end
	local grant = self.Grants[receipt.ProductId]
	if not grant then return retry end
	local playerId = receipt.PlayerId
	if typeof(playerId) ~= "number" or playerId < 1 or playerId % 1 ~= 0 then return retry end
	local player = Players:GetPlayerByUserId(playerId)
	if not player then return retry end
	local profile = self.Store:GetSession(player)
	if not profile then profile = self.Store:WaitForSession(player, 10) end
	if not profile or not profile:IsActive() then return retry end
	local succeeded, _, status = profile:Mutate(function(draft: {[string]: any})
		local processed = draft[self.Field]
		if typeof(processed) ~= "table" then return false end
		if processed[purchaseId] == true then return false end
		grant(draft, receipt)
		processed[purchaseId] = true
		return "GRANTED"
	end)
	if not succeeded then return retry end
	-- CANCELLED means the receipt was already recorded. Its save still must
	-- be confirmed, including after a prior transient/ambiguous save error.
	if status ~= nil and status ~= "CANCELLED" then return retry end
	local saved, saveStatus = profile:SaveAsync("critical")
	if not saved or saveStatus == "DEFERRED" then return retry end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- Call only from the server after constructing an explicit product grant map.
function NexusReceipts:Bind()
	MarketplaceService.ProcessReceipt = function(receipt)
		return self:ProcessReceipt(receipt)
	end
end

return NexusReceipts
