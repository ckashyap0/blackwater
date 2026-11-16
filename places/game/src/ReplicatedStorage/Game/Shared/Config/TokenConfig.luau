--!strict
-- TOKENS: consumables bought with Robux in the shop (GAMEPASSES tab, under the passes). Shared by the Lobby
-- and Game places (keep both copies identical).
--
-- Each token is a DEVELOPER PRODUCT, not a gamepass: a gamepass can only be bought once, a token can be
-- bought again and again. Create one per token on the Creator Dashboard (Monetization > Developer
-- Products) and paste its id into ProductId. With ProductId 0 the card shows COMING SOON.
-- Price is only the fallback label; the real price is read live from Roblox.
-- OnSale=false shows COMING SOON and hides the buy button. Keep ProductId, so a purchase Roblox is still
-- retrying gets delivered. Scare has no effect in play yet; Life has nothing to save you from until a floor can hurt you.
--
-- How many each player has is saved by TokenService (DataStore Store) and replicated as the player
-- attribute in Attr:   player:GetAttribute("EHScareTokens")  -> 3
-- Server code: TokenService:Get(player,"Scare") / :Add(player,"Life",1) / :Use(player,"Life") -> true if they had one
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Store="EHTokensV1",
	Tokens={
		{Id="Scare",Name="Spook Token",Attr="EHScareTokens",ProductId=3731064291,OnSale=false,Price=25,Amount=1,Model="JumpscareToken",Accent="16C454",
			Description="Scare a teammate with a jumpscare during a run."},
		{Id="Life",Name="Extra Life Token",Attr="EHLifeTokens",ProductId=3731064377,OnSale=false,Price=49,Amount=1,Model="LifeToken",Accent="CD3E48",
			Description="One extra life, used up when you would go down."},
	},
	-- the VIP gamepass comes with one Spook Token (given once, the first time a VIP owner joins)
	VipPassId=2017910251,
	VipGift={Scare=1},
})
