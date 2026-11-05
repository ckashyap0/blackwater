--!strict
-- Clothing sold in the lobby Gallery. Each mannequin in LobbyEnvironment.Gallery.Exhibits has an
-- "Outfit" attribute naming one entry below; holding E on it opens a panel with one BUY button per item,
-- which opens Roblox's own purchase prompt.
-- To add an outfit: add an entry here (Kind is just the button word: "Shirt", "Pants", ...), dress a
-- mannequin in it and set that mannequin's Outfit attribute to the entry's key.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Outfits={
		Facility={
			Name="Facility Set",
			Items={
				{Kind="Shirt",Label="Facility Vest",AssetId=103190496889034},
				{Kind="Pants",Label="Facility Pants",AssetId=101923763657712},
			},
		},
		Safety={
			Name="Safety Set",
			Items={
				{Kind="Shirt",Label="Safety Vest",AssetId=134682654735818},
				{Kind="Pants",Label="Dark Jeans",AssetId=129657893242642},
			},
		},
		DarkStreetwear={
			Name="Dark Streetwear",
			Items={
				{Kind="Shirt",Label="Dark Streetwear Shirt",AssetId=79434922388876},
				{Kind="Pants",Label="Dark Streetwear Pants",AssetId=132250922215879},
			},
		},
		Hazmat={
			Name="Hazmat Suit",
			Items={
				{Kind="Shirt",Label="Hazmat Suit Shirt",AssetId=73958045926749},
				{Kind="Pants",Label="Hazmat Suit Pants",AssetId=80790196110883},
			},
		},
	},
	-- The panel closes by itself once the player walks this far (studs) from the mannequin.
	CloseDistance=14,
	-- Hold time on the mannequin prompt (seconds); works as press-and-hold on phones, tablets and gamepads.
	HoldSeconds=.5,
})
