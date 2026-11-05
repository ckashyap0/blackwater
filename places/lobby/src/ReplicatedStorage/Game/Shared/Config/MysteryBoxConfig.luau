--!strict
-- MYSTERY BOXES (the shop's MYSTERY BOXES tab). Each box gives one random reward: a BOX EXCLUSIVE flashlight
-- skin, beam colour or name title that is never sold in the shop (CosmeticsConfig entries with Box = true), or a token
-- (Tokens below). M.Contents(box) lists what a box can give with each item's chance (the shop's
-- WHAT'S INSIDE view).
--   Jackpot = an extra roll made first: Chance percent to win that one item (the Vault's Supernova, which
--            nothing else can give).
--   Odds   = the chance of each rarity, in percent (shown on the card). Inside a rarity every item is
--            equally likely. An item's rarity comes from its coin price - the same tiers as the locker.
--   Already own what you got? You get Refund x the item's coin price back in coins instead.
--   Coin prizes (CoinPrizes below): a pile of coins in each rarity pool, paid straight into your balance.
-- Coin boxes: Coins = the price in coins.
-- Robux box: a DEVELOPER PRODUCT (bought again and again, which a gamepass can't be). Create it on the
--   Creator Dashboard (Monetization > Developer Products) and paste its id into ProductId. With 0 the
--   card shows COMING SOON. Price is only the fallback label; the real price is read live from Roblox.
-- Model = the box's 3D art in ReplicatedStorage.Game.ShopArt.Boxes.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
local Cos=require(script.Parent.CosmeticsConfig)
local M={
	Refund=.5,
	Order={"COMMON","RARE","EPIC","LEGENDARY","MYTHIC","ULTRA RARE"},
	Colors={COMMON="B4AFA6",RARE="5AA0FF",EPIC="B36BFF",LEGENDARY="E2B651",MYTHIC="FF4F8B",["ULTRA RARE"]="FF7AE0",JACKPOT="FFC24A"},
	-- tokens in the prize pools (never "already owned": you just get one more). Rarity = which pool.
	Tokens={
		{Id="Scare",Rarity="RARE"},
		{Id="Life",Rarity="EPIC"},
	},
	-- coin prizes in the prize pools: Amount coins, Rarity = which pool, Model = its art in ShopArt
	CoinPrizes={
		{Id="Coins200",Amount=200,Rarity="COMMON",Model="CoinPack_Handful"},
		{Id="Coins500",Amount=500,Rarity="RARE",Model="CoinPack_Pouch"},
		{Id="Coins1000",Amount=1000,Rarity="EPIC",Model="CoinPack_Stack"},
		{Id="Coins2500",Amount=2500,Rarity="LEGENDARY",Model="CoinPack_Chest"},
		{Id="Coins5000",Amount=5000,Rarity="MYTHIC",Model="CoinPack_Vault"},
		{Id="Coins10000",Amount=10000,Rarity="ULTRA RARE",Model="CoinPack_Hoard"},
	},
	Boxes={
		{Id="Crate",Name="Rusty Crate",Coins=500,Model="BoxCrate",Accent="C0683A",
			Blurb="A dented old supply crate. Mostly commons, the odd lucky find.",
			Odds={COMMON=60,RARE=28,EPIC=10,LEGENDARY=2}},
		{Id="Case",Name="Midnight Case",Coins=1000,Model="BoxCase",Accent="8A3CFF",
			Blurb="A locked black case, humming with purple light.",
			Odds={RARE=35,EPIC=35,LEGENDARY=22,MYTHIC=8}},
		{Id="Vault",Name="Abyssal Case",ProductId=3718061828,Price=99,Model="BoxVault",Accent="46D26E",Featured=true,
			Blurb="The best odds in the building - and a 1% shot at the Supernova.",
			Odds={EPIC=22,LEGENDARY=40,MYTHIC=32,["ULTRA RARE"]=6},
			Jackpot={Slot="Flashlight",Id="Supernova",Chance=1}},
	},
}
-- the rarity of a coin-shop item (matches the locker's tiers)
function M.Rarity(slot:string,e:any):string
	if e.Rarity then return e.Rarity end
	local p=e.Price or 0
	if slot=="Beam" then
		if e.Rainbow then return "ULTRA RARE" end
		if p>=2500 then return "MYTHIC" elseif p>=1500 then return "LEGENDARY" elseif p>=800 then return "EPIC" elseif p>=400 then return "RARE" end
		return "COMMON"
	end
	if p>=20000 then return "ULTRA RARE" elseif p>=3200 then return "MYTHIC" elseif p>=1250 then return "LEGENDARY" elseif p>=1000 then return "EPIC" elseif p>=650 then return "RARE" end
	return "COMMON"
end
-- what a box can give: {slot, id, tier, chance (percent), jackpot}, best first
function M.Contents(box:any):{any}
	local pools={}
	local function add(r,item)pools[r]=pools[r] or {};table.insert(pools[r],item) end
	for _,slot in {"Flashlight","Beam","Title"} do
		for _,e in Cos[slot] do if e.Box==true then add(M.Rarity(slot,e),{slot=slot,id=e.Id}) end end
	end
	for _,t in M.Tokens do add(t.Rarity,{slot="Token",id=t.Id}) end
	for _,c in M.CoinPrizes do add(c.Rarity,{slot="Coins",id=c.Id}) end
	local total=0
	for r,w in box.Odds do if pools[r] then total+=w end end
	local jp=box.Jackpot and (box.Jackpot.Chance or 0) or 0
	local out={}
	if box.Jackpot then table.insert(out,{slot=box.Jackpot.Slot,id=box.Jackpot.Id,tier="JACKPOT",chance=jp,jackpot=true}) end
	for i=#M.Order,1,-1 do
		local r=M.Order[i];local w=box.Odds[r]
		if w and pools[r] and total>0 then
			for _,it in pools[r] do table.insert(out,{slot=it.slot,id=it.id,tier=r,chance=(100-jp)*(w/total)/#pools[r]}) end
		end
	end
	return out
end
-- a coin prize by its Id (nil if there is none)
function M.CoinPrize(id:string):any
	for _,c in M.CoinPrizes do if c.Id==id then return c end end
	return nil
end
return Freeze(M)
