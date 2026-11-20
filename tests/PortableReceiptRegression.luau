--!strict
-- Requires the real NexusReceipts module loaded by the portable harness.
local receiptPassed, receiptFailed = 0, 0
local function receiptTest(name, callback)
	local ok, err = pcall(callback)
	if ok then receiptPassed += 1; print("PASS", name) else receiptFailed += 1; print("FAIL", name, err) end
end

local function newReceiptFixture()
	Enum.ProductPurchaseDecision = {PurchaseGranted = "GRANTED", NotProcessedYet = "RETRY"}
	local session = profile({DetectDirectChanges = false})
	assert(session:SetDefault("ProcessedReceipts", {}))
	local store = session.Store
	local fakePlayer = {UserId = 42}
	services.Players.GetPlayerByUserId = function(_, id)
		return id == 42 and fakePlayer or nil
	end
	store.GetSession = function(_, who)
		return who == fakePlayer and session or nil
	end
	local saved = true
	local saves = 0
	session.SaveAsync = function(_self, priority)
		assert(priority == "critical")
		saves += 1
		if not saved then return false, "NETWORK_ERROR" end
		return true
	end
	local service = NexusReceipts.new(store, {
		[111] = function(data)
			data.Coins += 50
		end,
	})
	return service, session, function(value) saved = value end, function() return saves end
end

receiptTest("Receipt grants exactly once in a live session", function()
	local service, session, _, saves = newReceiptFixture()
	local receipt = {PlayerId = 42, ProductId = 111, PurchaseId = "receipt-1"}
	assert(service:ProcessReceipt(receipt) == "GRANTED")
	assert(service:ProcessReceipt(receipt) == "GRANTED")
	assert(session.Data.Coins == 60 and session.Data.ProcessedReceipts["receipt-1"] == true)
	assert(saves() == 2)
end)

receiptTest("Ambiguous critical save retries without granting twice", function()
	local service, session, setSaved = newReceiptFixture()
	local receipt = {PlayerId = 42, ProductId = 111, PurchaseId = "receipt-2"}
	setSaved(false)
	assert(service:ProcessReceipt(receipt) == "RETRY")
	assert(session.Data.Coins == 60)
	setSaved(true)
	assert(service:ProcessReceipt(receipt) == "GRANTED")
	assert(session.Data.Coins == 60)
end)

receiptTest("Unknown products and invalid receipt IDs are never granted", function()
	local service, session = newReceiptFixture()
	assert(service:ProcessReceipt({PlayerId = 42, ProductId = 222, PurchaseId = "no"}) == "RETRY")
	assert(service:ProcessReceipt({PlayerId = 42, ProductId = 111, PurchaseId = ""}) == "RETRY")
	assert(session.Data.Coins == 10)
end)

print(string.format("v9 receipt tests: %d passed, %d failed", receiptPassed, receiptFailed))
assert(receiptFailed == 0, "Receipt regressions failed")
