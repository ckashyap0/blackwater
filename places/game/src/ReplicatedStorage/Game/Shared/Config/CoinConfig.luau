--!strict
-- Coins. Shared by the Lobby and Game places (keep both copies identical).
-- Saved in their own DataStore (Store), so a balance follows the player between places and rejoins.
--
-- COIN PACKS (Robux -> coins) are Developer Products. Create one per pack on the Creator Dashboard
-- (Monetization > Developer Products), then paste its id into ProductId below. A pack whose
-- ProductId is 0 shows "COMING SOON" in the shop and cannot be bought. The price on the card is read
-- live from Roblox; Price here is the dashboard price (used only as a fallback label).
--
-- Coins EARNED in game (EconomyConfig floor rewards etc.) are doubled for owners of the 2x Coins
-- gamepass (TwoXPassId). Bought coins are never doubled.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Store="EHCoinsV1",
	TwoXPassId=2017340275,
	EarnMultiplier=2,
	-- left to right, top to bottom in the shop's COINS tab
	Packs={
		-- base rate 4 coins per Robux; Bonus = how much more than that the pack gives
		{Id="Handful",  Name="Pocket Change",  Coins=100,  Bonus=0,  Price=25,   ProductId=3717544877},
		{Id="Pouch",    Name="Coin Pouch",     Coins=250,  Bonus=25, Price=50,   ProductId=3717544952},
		{Id="Stack",    Name="Coin Stack",     Coins=560,  Bonus=40, Price=100,  ProductId=3717545016},
		{Id="Chest",    Name="Treasure Chest", Coins=1200, Bonus=50, Price=200,  ProductId=3717545159},
		{Id="Vault",    Name="Gold Vault",     Coins=3200, Bonus=60, Price=500,  ProductId=3717545213},
		{Id="Hoard",    Name="Midas's Treasury", Coins=7000, Bonus=75, Price=999, ProductId=3717546001, BestValue=true},
	},
	-- how often earned coins are written to the DataStore (seconds); also saved when you leave
	SaveInterval=30,
})
