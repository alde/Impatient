----
-- Initialize variables
Impatient = {}

local original_click_events = {}
local list_of_quests = {}
local _G = getfenv(0)

----
-- Messages output to the chat
local L = {
	["text_no_turn_in"] = "No longer impatiently turning in \"%s\".",
	["text_no_skip"] = "No longer impatiently skipping \"%s\".",
	["text_no_accept"] = "No longer impatiently accepting \"%s\".",

	["text_accept"] = "Now impatiently accepting \"%s\". Hold CTRL and click the option again to stop.",
	["text_skip"] = "Now impatiently skipping \"%s\". Hold ALT and click the option again to stop.",
	["text_turn_in"] = "Now impatiently turning in \"%s\". Hold ALT and click the option again to stop.",
}

----
-- Try to sanitize strings from extra text that other addons usually add
--
-- params:
-- string 	text 	Text from the UI to sanitize
--
-- return:
-- string 			sanitized text string
function Sanitize(text)
	-- Strip [<level>] <quest title>
	text = string.gsub(text, "%[(.+)%]", "")
	-- Strip color codes
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x(.+)|r", "%1")
	-- Strip (low level) at the end of a quest
	text = string.gsub(text, "(.+) %((.+)%)", "%1")

	return string.trim(text)
end


---
-- Print message to chat
--
-- params:
-- string 	msg 	Message to print
--
-- returns:
-- nil				no return value
local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99Impatient|r: " .. msg)
end


----
-- Toggle the auto skipping of gossip
--
-- returns:
-- nil 					No return value
function ToggleGossipSkip(self)

	-- If it is already skipped, remove it.
	local text = Sanitize(self:GetText())
	local questName = string.lower(text)

	if (Impatient_List[questName]) then
		if (self.type ~= "Gossip") then
			Print(
				string.format(
					L["text_no_turn_in"],
					text
				)
			)

			Impatient_List[questName] = nil

			return
		end

		Print(
			string.format(
				L["text_no_skip"],
				text
			)
		)

		Impatient_List[questName] = nil

		return
	end

	-- Gossip doesn't need any items.
	if (self.type == "Gossip") then
		Print(
			string.format(
				L["text_skip"],
				text
			)
		)

		Impatient_List[questName] = true

		return
	end

	-- It's not gossip, so it could possibly need items
	Print(
		string.format(
			L["text_turn_in"],
			text
		)
	)

	Impatient_List[questName] = {}

	return
end


----
-- Toggles auto accepting of quests
--
-- returns:
-- nil 				No return value
function ToggleAccept(self)
	local text = Sanitize(self:GetText())
	local questName = string.lower(text)

	-- If it's already being accepted, remove it.
	if (Impatient_Accept[questName]) then
		Print(string.format(L["text_no_accept"], text))
		Impatient_Accept[questName] = nil

		return
	end

	Print(string.format(L["text_accept"], text))
	Impatient_Accept[questName] = true

end


----
-- Handler for clicks
--
-- returns:
-- nil 					No return value
function ClickHandler(self, ...)

	-- Holnding down ALT adds a new topic to skip, or removes it if it's currently
	-- being skipped.
	if (IsAltKeyDown() and self:GetText()) then
		ToggleGossipSkip(self)

	-- Holding Control on a non-gossip adds auto accepting of the quest, or
	-- removes it if it's currently being accepted.
	elseif (IsControlKeyDown() and self:GetText() and self.type ~= "Gossip") then
		ToggleAccept(self)

		return
	end

	original_click_events[self:GetName()](self, ...)
end


----
-- Check if we need to skip anything
--
-- returns:
-- nil 					No return value
function Impatient:GOSSIP_SHOW()
	if (not GossipFrame.buttonIndex or IsShiftKeyDown()) then
		return
	end

	-- Recycle quests
	for quest in pairs(list_of_quests) do
		list_of_quests[quest] = nil
	end

	-- List all available quests
	for i = 1, GossipFrame.buttonIndex do
		local button = _G["GossipTitleButton" .. i]

		if (not original_click_events["GossipTitleButton" .. i]) then
			original_click_events["GossipTitleButton" .. i] = button:GetScript("OnClick")
			button:SetScript("OnClick", ClickHandler)
		end

		if (button:IsVisible() and button:GetText()) then
			text = string.lower(
				Sanitize(
					button:GetText()
				)
			)
			list_of_quests[text] = button
		end
	end

	-- Let's see what to skip
	for name, button in pairs(list_of_quests) do
		if ((self:IsAutoQuest(name, list_of_quests) and self:IsCompleted(name)) or (button.type == "Available" and Impatient_Accept[name])) then

			if (button.type == "Available") then
				SelectGossipAvailableQuest(button:GetID())
				return
			end

			if (button.type == "Active") then
				SelectGossipActiveQuest(button:GetID())
				return
			end

			SelectGossipOption(button:GetID())
			return
		end
	end
end


----
-- Check if QUEST_PROGRESS should be skipped aswell.
--
-- returns:
-- nil 					No return value
function Impatient:QUEST_PROGRESS()
	if (IsShiftKeyDown()) then
		return
	end

	-- Do we need to find items?
	local questName = string.lower(string.trim(GetTitleText()))

	-- If It's got items, do we need to scan them?
	if (GetNumQuestItems() > 0) then
		local data = Impatient_List[questName]

		if (type(data) == "table") then
			for quest in pairs(Impatient_List[questName]) do
				Impatient_List[questName][quest] = nil
			end

			--[[
				Cache how many we need, store by itemid.
				This in practice means we need to complete a quest with items
				once at first, but we don't have to cache a million quest items.
			]]--
			for index = 1, GetNumQuestItems() do
				local itemLink = GetQuestItemLink("required", index)

				if (itemLink) then
					local itemid = string.match(
						itemLink,
						"|c.+|Hitem:([0-9]+):(.+)|h%[(.+)%]|h|r"
					)

					itemid = tonumber(itemid)

					if (itemid) then
						Impatient_List[questName][itemid] = select(
							3,
							GetQuestItemInfo("required", index)
						)
					end
				end
			end
		end

	-- No items required
	elseif (Impatient_List[questName]) then
		Impatient_List[questName] = true
	end

	for quest in pairs(list_of_quests) do
		list_of_quests[quest] = nil
	end

	list_of_quests[string.lower(Sanitize(GetTitleText()))] = true

	-- Alright! Complete
	if (IsQuestCompletable() and self:IsAutoQuest(GetTitleText(), list_of_quests)) then
		CompleteQuest()
	end
end


----
-- Handler for QUEST_COMPLETE events
--
-- returns:
-- nil 					No return value
function Impatient:QUEST_COMPLETE()
	local questName = string.lower(string.trim(GetTitleText()))

	if (not Impatient_List[questName]) then
		return
	end

	-- Flag quests with no items as being auto completable
	if (type(Impatient_List[questName]) == "table") then
		local hasItem

		for itemid in pairs(Impatient_List[questName]) do
			hasItem = true
			break
		end

		if (not hasItem) then
			Impatient_List[questName] = true
		end
	end

	for quest in pairs(list_of_quests) do
		list_of_quests[quest] = nil
	end

	list_of_quests[string.lower(Sanitize(GetTitleText()))] = true

	if (IsShiftKeyDown() and not self:IsAutoQuest(GetTitleText(), list_of_quests)) then
		return
	end

	if (QuestFrameRewardPanel.itemChoice == 0 and GetNumQuestChoices() > 0) then
		QuestChooseRewardError()

		return
	end

	PlaySound("iglist_of_questsComplete")
	GetQuestReward(QuestFrameRewardPanel.itemChoice)
end


----
-- Handler for QUEST_DETAIL event
--
-- returns:
-- nil					No return value
function Impatient:QUEST_DETAIL()
	local title = string.lower(
		string.trim(
			GetTitleText()
		)
	)

	if (not IsShiftKeyDown() and Impatient_Accept[title]) then
		AcceptQuest()
	end
end


----
-- Check if a quest is completed
--
-- params:
-- string 	name 		Quest name
--
-- returns:
-- boolean 				True if the quest is completed, false if not
function Impatient:IsCompleted(name)
	for index=1, GetNumQuestLogEntries() do
		local questName, _, _, _, _, _, isComplete = GetQuestLogTitle(index)

		if (name == Sanitize(string.lower(questName))) then
			if ((isComplete and isComplete > 0) or GetNumQuestLeaderBoards(index) == 0) then
				return true
			end

			return false
		end
	end

	-- Default to completed if we don't have the quest,
	-- which shouldn't happen really
	return true
end


----
-- Check if we acutually have the required items for the quest to automatically
-- be handed in
--
-- params:
-- list  	list 		List of items
--
-- returns:
-- boolean 				True if we have the items
function Impatient:HasItems(list)
	for itemid in pairs(list) do
		return true
	end

	return false
end


----
-- Check if it's an automatically completable quest
--
-- params:
-- string 	name 		Quest name
-- list 	list_of_quests 	List of quests
--
-- returns
-- boolean 				True if it's an automatically completable quest
function Impatient:IsAutoQuest(name, list_of_quests)
	-- Invalid quest name
	if (not name) then
		return false
	end

	name = Sanitize(string.lower(name))

	local data = Impatient_List[name]

	-- Not in the list of automatics
	if (not data) then
		return false
	end

	-- No item requirements, so save some time
	if (type(data) ~= "table" ) then
		return true
	end

	-- Make sure we have the items required for this quest
	local hasItems
	for itemid, quantity in pairs(data) do
		hasItems = true

		if (GetItemCount(itemid) < quantity) then
			return false
		end
	end

	-- Don't have item data yet but it's a table, so can't auto-complete
	if (not hasItems) then
		return false
	end

	-- Shitty check to see if we have enough items
	local questName = name
	local highestItems = data
	for name, data in pairs(Impatient_List) do
		if (name ~= questName and type(data) == "table" and self:HasItems(data) and (list_of_quests or (list_of_quests and list_of_quests[name]))) then
			local required = 0
			local found = 0

			-- Check it against our saved quests
			for itemid, quantity in pairs(data) do
				required = required + 1

				if (highestItems[itemid] and quantity >= highestItems[itemid] and GetItemCount(itemid) >= quantity) then
					found = found + 1
				end
			end

			-- This quest needs than ours, so don't auto accept
			if (found >= required) then
				return false
			end
		end
	end

 	return true
end


----
-- Initialize the Impatient Addon
--
-- return:
-- nil 				No return value
function Impatient:Start()

	Impatient_List = Impatient_List or {}
	Impatient_Accept = Impatient_Accept or {}

	-- Hookpoint for automatically accepting quests
	local defaultAcceptScript = QuestFrameAcceptButton:GetScript("OnClick")

	QuestFrameAcceptButton:SetScript(
		"OnClick",
		function(...)
			if (IsControlKeyDown() and GetTitleText()) then
				local text = Sanitize(GetTitleText())
				local questName = string.lower(text)

				if (Impatient_Accept[questName]) then
					Print(
						string.format(
							L["text_no_accept"],
							text
						)
					)
					Impatient_Accept[questName] = nil

					return
				end
				Print(
					string.format(
						L["text_accept"],
						text
					)
				)
				Impatient_Accept[questName] = true

				return
			end

			if (defaultAcceptScript) then
				defaultAcceptScript(self, ...)
			end
		end
	)

	-- Hookpoint for automatically turning in quests
	local defaultCompleteScript = QuestFrameCompleteQuestButton:GetScript("OnClick")

	QuestFrameCompleteQuestButton:SetScript(
		"OnClick",
		function(...)
			if (IsAltKeyDown() and GetTitleText()) then
				local text = Sanitize(GetTitleText())
				local questName = string.lower(text)

				if (Impatient_List[questName]) then
					Impatient_List[questName] = nil
					Print(
						string.format(
							L["text_no_turn_in"],
							text
						)
					)

					return
				end

				Impatient_List[questName] = {}
				Print(
					string.format(
						L["text_turn_in"],
						text
					)
				)
				return
			end

			if (defaultCompleteScript) then
				defaultCompleteScript(self, ...)
			end
		end

	)
end


----
-- Create addon in the scope of WoW
local frame = CreateFrame("Frame")


----
-- Register needed events
frame:RegisterEvent("QUEST_PROGRESS")
frame:RegisterEvent("QUEST_COMPLETE")
frame:RegisterEvent("QUEST_DETAIL")
frame:RegisterEvent("GOSSIP_SHOW")
frame:RegisterEvent("ADDON_LOADED")


----
-- Start the addon if it should be
frame:SetScript("OnEvent", function(self, event, addon)
	if (event == "ADDON_LOADED" and addon == "Impatient") then
		Impatient:Start()
		self:UnregisterEvent("ADDON_LOADED")
	elseif (event ~= "ADDON_LOADED") then
		Impatient[event](Impatient)
	end
end)