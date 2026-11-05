--!strict
-- Unlockable cosmetics. Shared by the Lobby and Game places (keep both copies identical).
-- Slots: Title (tag in front of your name in chat), Flashlight (the flashlight you hold in the descent)
-- and Beam (the colour of its light). Some are found in the lobby's secret room (SecretRoom.Collectibles),
-- some come with a gamepass, and the ones with a Price are bought with coins in the lobby SHOP
-- (FLASHLIGHT SKINS / BEAM COLORS tabs). Everything owned is equipped from the LOCKER, one tab per slot.
-- Saved in their own DataStore (Store) so they follow the player between places and rejoins.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Store="EHCosmeticsV1",
	Slots={"Title","Flashlight","Beam"},
	-- LOCKER tabs, left to right
	Tabs={
		{Slot="Title",Label="TITLES"},
		{Slot="Flashlight",Label="SKINS"},
		{Slot="Beam",Label="COLORS"},
	},
	Title={
		{Id="Default",Name="Default",Label="DEFAULT"},
		{Id="Secret",Name="Secret",Label="SECRET",Color="#B36BFF",Hint="Hidden somewhere behind the SECRET door"},
		{Id="VIP",Name="VIP",Label="VIP",Color="#E2B651",Pass="VIP",Hint="Comes with the VIP gamepass"},
		-- LEADERBOARD TITLES (lobby boards): owned while you are in that board's top 100; shown as
		-- "#3 DONOR" (top 10) or "TOP 100 DONOR"; taken off automatically if you drop out
		{Id="DonorTag",Name="Top Donor",Label="TOP DONOR",Color="#5ED27A",Leaderboard="Donor",Hint="Be in the top 100 on the TOP DONORS board in the lobby"},
		{Id="CoinTag",Name="Top Coins",Label="TOP COINS",Color="#F2C14E",Leaderboard="Coin",Hint="Be in the top 100 on the TOP COINS board in the lobby"},
		-- MYSTERY BOX EXCLUSIVE TITLES (Box = true, Rarity = which boxes can drop them; Value = coins back when owned)
		{Id="Survivor",Name="Survivor",Label="SURVIVOR",Color="#C9C2B4",Box=true,Rarity="COMMON",Value=150,Hint="Only found in MYSTERY BOXES"},
		{Id="NightShift",Name="Night Shift",Label="NIGHT SHIFT",Color="#8FB0C8",Box=true,Rarity="COMMON",Value=150,Hint="Only found in MYSTERY BOXES"},
		{Id="Lurker",Name="Lurker",Label="LURKER",Color="#5AA0FF",Box=true,Rarity="RARE",Value=400,Hint="Only found in MYSTERY BOXES"},
		{Id="Drowned",Name="Drowned",Label="DROWNED",Color="#2FC8C8",Box=true,Rarity="EPIC",Value=800,Hint="Only found in MYSTERY BOXES"},
		{Id="Unbroken",Name="Unbroken",Label="UNBROKEN",Color="#E2B651",Box=true,Rarity="LEGENDARY",Value=1500,Hint="Only found in MYSTERY BOXES"},
		{Id="Abyssborn",Name="Abyssborn",Label="ABYSSBORN",Color="#FF4F8B",Box=true,Rarity="MYTHIC",Value=3000,Hint="Only found in MYSTERY BOXES"},
		{Id="Blackwater",Name="Blackwater",Label="BLACKWATER",Color="#FF7AE0",Box=true,Rarity="ULTRA RARE",Value=6000,Hint="Only in the ABYSSAL CASE"},
	},
	-- Model = name of the held model in ReplicatedStorage.Game.Assets (Game place) and of its shop
	-- preview in ReplicatedStorage.Game.ShopArt.Skins (Lobby). Price = coins in the shop.
	Flashlight={
		-- everyone's starting flashlight: the rusty one (it used to be sold in the shop as "Rustbelt")
		{Id="Default",Name="Rustbelt",Label="RUSTBELT",Color="#C0683A",Model="SkinRustbelt"},
		{Id="Standard",Name="Standard Issue",Label="STANDARD ISSUE",Color="#6E747C",Model="SkinStandard",Price=400},
		{Id="Phantom",Name="Phantom Flashlight",Label="PHANTOM FLASHLIGHT",Color="#B36BFF",Model="PhantomFlashlight",Hint="Hidden somewhere behind the SECRET door"},
		{Id="VIP",Name="VIP Flashlight",Label="VIP FLASHLIGHT",Color="#E2B651",Model="VIPFlashlight",Pass="VIP",Hint="Comes with the VIP gamepass"},
		{Id="Gunmetal",Name="Gunmetal",Label="GUNMETAL",Color="#9AA3AE",Model="SkinGunmetal",Price=500},
		{Id="Hazard",Name="Hazard",Label="HAZARD",Color="#F0C020",Model="SkinHazard",Price=600},
		{Id="Lantern",Name="Lantern Brass",Label="LANTERN BRASS",Color="#C8964A",Model="SkinLantern",Price=650},
		{Id="Bone",Name="Bone",Label="BONE",Color="#E2D8BE",Model="SkinBone",Price=750},
		{Id="Bloodline",Name="Bloodline",Label="BLOODLINE",Color="#D2283A",Model="SkinBloodline",Price=900},
		{Id="Abyss",Name="Abyss",Label="ABYSS",Color="#3CC8E6",Model="SkinAbyss",Price=1000},
		{Id="Frostbite",Name="Frostbite",Label="FROSTBITE",Color="#B4E6FF",Model="SkinFrostbite",Price=1100},
		{Id="Obsidian",Name="Obsidian",Label="OBSIDIAN",Color="#E6323C",Model="SkinObsidian",Price=1250},
		{Id="Verdigris",Name="Verdigris",Label="VERDIGRIS",Color="#5AAA96",Model="SkinVerdigris",Price=1500},
		-- top tier (ServerStorage.FlashlightSkinBuilderExtra); Rarity overrides the tier shown in the shop
		{Id="Circuit",Name="Circuit",Label="CIRCUIT",Color="#20FF5A",Model="SkinCircuit",Price=1750},
		{Id="JadeDragon",Name="Jade Dragon",Label="JADE DRAGON",Color="#2E9E6E",Model="SkinJadeDragon",Price=2000},
		{Id="Synthwave",Name="Synthwave",Label="SYNTHWAVE",Color="#FF3CC8",Model="SkinSynthwave",Price=2250},
		{Id="Pharaoh",Name="Pharaoh",Label="PHARAOH",Color="#F2C14E",Model="SkinPharaoh",Price=2500},
		{Id="Toxic",Name="Toxic Canister",Label="TOXIC CANISTER",Color="#6CFF3A",Model="SkinToxic",Price=2800},
		{Id="Clockwork",Name="Clockwork",Label="CLOCKWORK",Color="#C8964A",Model="SkinClockwork",Price=3200},
		{Id="Diamond",Name="Diamond",Label="DIAMOND",Color="#CFF4FF",Model="SkinDiamond",Price=3600},
		{Id="Inferno",Name="Inferno",Label="INFERNO",Color="#FF6A1A",Model="SkinInferno",Price=4000},
		{Id="Plasma",Name="Plasma Core",Label="PLASMA CORE",Color="#3CD2FF",Model="SkinPlasma",Price=4500},
		{Id="Reaper",Name="Reaper",Label="REAPER",Color="#9B5BFF",Model="SkinReaper",Price=5000},
		{Id="Celestial",Name="Celestial",Label="CELESTIAL",Color="#F6DC8A",Model="SkinCelestial",Price=6000},
		{Id="Void",Name="Void Rift",Label="VOID RIFT",Color="#8A3CFF",Model="SkinVoid",Price=7500},
		{Id="UFO",Name="Close Encounter",Label="CLOSE ENCOUNTER",Color="#7CFF6A",Model="SkinUFO",Price=10000},
		{Id="Aurora",Name="Aurora",Label="AURORA",Color="#FF7AE0",Model="SkinAurora",Price=25000,Rarity="ULTRA RARE"},
		-- MYSTERY BOX EXCLUSIVES: never sold in the shop (no Price) - the only way to get them is a mystery box.
		-- Box = true: any box whose odds include its Rarity can drop it; "Jackpot" = only a box's jackpot roll
		-- (Config.MysteryBoxConfig). Value = what it counts as in coins (the refund when you already own it).
		{Id="Bunker",Name="Bunker",Label="BUNKER",Color="#55603A",Model="SkinBunker",Box=true,Rarity="COMMON",Value=300,Hint="Only found in MYSTERY BOXES"},
		{Id="CopperCoil",Name="Copper Coil",Label="COPPER COIL",Color="#B87333",Model="SkinCopperCoil",Box=true,Rarity="RARE",Value=600,Hint="Only found in MYSTERY BOXES"},
		{Id="DeepSea",Name="Deep Sea",Label="DEEP SEA",Color="#2FA8C8",Model="SkinDeepSea",Box=true,Rarity="EPIC",Value=1100,Hint="Only found in MYSTERY BOXES"},
		{Id="Glitch",Name="Glitch",Label="GLITCH",Color="#00F0FF",Model="SkinGlitch",Box=true,Rarity="LEGENDARY",Value=2200,Hint="Only found in MYSTERY BOXES"},
		{Id="Hex",Name="Hex Totem",Label="HEX TOTEM",Color="#FF3B2F",Model="SkinHex",Box=true,Rarity="MYTHIC",Value=4200,Hint="Only found in MYSTERY BOXES"},
		{Id="Supernova",Name="Supernova",Label="SUPERNOVA",Color="#FFC24A",Model="SkinSupernova",Box="Jackpot",Rarity="ULTRA RARE",Value=20000,Hint="The ABYSSAL CASE's 1% jackpot - nowhere else"},
	},
	-- Beam = light colour, Bounce = the soft light it throws back on your hands. Price = coins in the shop.
	Beam={
		{Id="Default",Name="Warm White",Label="WARM WHITE",Beam={237,231,196},Bounce={169,177,145}},
		{Id="Phantom",Name="Phantom Purple",Label="PHANTOM PURPLE",Color="#B36BFF",Beam={168,84,255},Bounce={132,86,200},Hint="Comes with the Phantom Flashlight"},
		{Id="VIP",Name="VIP Emerald",Label="VIP EMERALD",Color="#46D26E",Beam={110,235,150},Bounce={90,170,115},Pass="VIP",Hint="Comes with the VIP gamepass"},
		{Id="Amber",Name="Amber Alert",Label="AMBER ALERT",Color="#FFB03C",Beam={255,176,60},Bounce={180,130,70},Price=200},
		{Id="Sodium",Name="Sodium Lamp",Label="SODIUM LAMP",Color="#FF872D",Beam={255,135,45},Bounce={170,100,50},Price=250},
		{Id="Crimson",Name="Crimson",Label="CRIMSON",Color="#DC2828",Beam={220,40,40},Bounce={150,50,50},Price=300},
		{Id="Glacier",Name="Glacier",Label="GLACIER",Color="#A0D7FF",Beam={160,215,255},Bounce={110,150,180},Price=300},
		{Id="Toxic",Name="Toxic",Label="TOXIC",Color="#A0FF46",Beam={160,255,70},Bounce={110,170,70},Price=350},
		{Id="Rose",Name="Rose",Label="ROSE",Color="#FF78AF",Beam={255,120,175},Bounce={180,90,130},Price=350},
		{Id="Abyssal",Name="Abyssal",Label="ABYSSAL",Color="#28D2E1",Beam={40,210,225},Bounce={40,140,150},Price=400},
		{Id="Ghost",Name="Ghost Light",Label="GHOST LIGHT",Color="#A096C8",Beam={160,150,200},Bounce={107,101,134},Price=450},
		{Id="Solar",Name="Solar Gold",Label="SOLAR GOLD",Color="#FFE13C",Beam={255,225,60},Bounce={171,151,40},Price=500},
		{Id="Arc",Name="Arc Blue",Label="ARC BLUE",Color="#5A82FF",Beam={90,130,255},Bounce={70,95,180},Price=600},
		{Id="Mint",Name="Mint",Label="MINT",Color="#9CFFD2",Beam={156,255,210},Bounce={106,173,142},Price=700},
		{Id="Peach",Name="Peach",Label="PEACH",Color="#FFB48C",Beam={255,180,140},Bounce={173,122,95},Price=750},
		{Id="Lavender",Name="Lavender",Label="LAVENDER",Color="#C3A5FF",Beam={195,165,255},Bounce={132,112,173},Price=800},
		{Id="Coral",Name="Coral",Label="CORAL",Color="#FF6E6E",Beam={255,110,110},Bounce={173,74,74},Price=850},
		{Id="Bronze",Name="Bronze",Label="BRONZE",Color="#B4783C",Beam={180,120,60},Bounce={121,80,40},Price=900},
		{Id="Jade",Name="Jade",Label="JADE",Color="#00A86B",Beam={0,168,107},Bounce={0,113,72},Price=1000},
		{Id="Chartreuse",Name="Chartreuse",Label="CHARTREUSE",Color="#D4FF00",Beam={212,255,0},Bounce={144,173,0},Price=1100},
		{Id="Cobalt",Name="Cobalt",Label="COBALT",Color="#2A5CFF",Beam={42,92,255},Bounce={28,62,173},Price=1200},
		{Id="Magenta",Name="Magenta",Label="MAGENTA",Color="#FF2FD0",Beam={255,47,208},Bounce={173,31,141},Price=1300},
		{Id="BloodMoon",Name="Blood Moon",Label="BLOOD MOON",Color="#9E0A1A",Beam={158,10,26},Bounce={107,6,17},Price=1500},
		{Id="Ultraviolet",Name="Ultraviolet",Label="ULTRAVIOLET",Color="#8A2BFF",Beam={138,43,255},Bounce={93,29,173},Price=1750},
		{Id="Infrared",Name="Infrared",Label="INFRARED",Color="#FF1F6B",Beam={255,31,107},Bounce={173,21,72},Price=2000},
		{Id="Spectral",Name="Spectral",Label="SPECTRAL",Color="#D2FFFF",Beam={210,255,255},Bounce={141,171,171},Price=2500},
		-- Rainbow = true: the light cycles through every colour (EquipmentController / shop / locker animate it)
		{Id="Rainbow",Name="Rainbow",Label="RAINBOW",Color="#FF7AE0",Beam={255,255,255},Bounce={190,190,190},Price=5000,Rainbow=true},
		-- MYSTERY BOX EXCLUSIVES (see the flashlights above). Pulse = a second colour the light slowly drifts to and back.
		{Id="Dusk",Name="Dusk",Label="DUSK",Color="#A85C8C",Beam={168,92,140},Bounce={113,62,94},Box=true,Rarity="COMMON",Value=150,Hint="Only found in MYSTERY BOXES"},
		{Id="Seafoam",Name="Seafoam",Label="SEAFOAM",Color="#0F8C8C",Beam={15,140,140},Bounce={10,94,94},Box=true,Rarity="COMMON",Value=150,Hint="Only found in MYSTERY BOXES"},
		{Id="Witchfire",Name="Witchfire",Label="WITCHFIRE",Color="#46FF78",Beam={70,255,120},Bounce={48,170,82},Box=true,Rarity="RARE",Value=450,Hint="Only found in MYSTERY BOXES"},
		{Id="Nightshade",Name="Nightshade",Label="NIGHTSHADE",Color="#C8106E",Beam={200,16,110},Bounce={130,10,72},Box=true,Rarity="EPIC",Value=900,Hint="Only found in MYSTERY BOXES"},
		{Id="Hellfire",Name="Hellfire",Label="HELLFIRE",Color="#FF460A",Beam={255,70,10},Bounce={170,50,10},Box=true,Rarity="LEGENDARY",Value=1600,Hint="Only found in MYSTERY BOXES"},
		{Id="AuroraShift",Name="Aurora Shift",Label="AURORA SHIFT",Color="#00FFC8",Beam={0,255,200},Bounce={0,171,134},Pulse={170,90,255},Box=true,Rarity="MYTHIC",Value=3000,Hint="Only found in MYSTERY BOXES"},
		{Id="EventHorizon",Name="Event Horizon",Label="EVENT HORIZON",Color="#5A1EBE",Beam={90,30,190},Bounce={60,20,127},Pulse={225,240,255},Box=true,Rarity="ULTRA RARE",Value=6000,Hint="Only in the ABYSSAL CASE"},
	},
	-- secret-room pickups: model name -> what taking it unlocks
	Collectibles={
		SecretTag={Name="[Secret] title",Grants={{"Title","Secret"}}},
		PhantomFlashlight={Name="Phantom Flashlight",Grants={{"Flashlight","Phantom"},{"Beam","Phantom"}}},
	},
	-- gamepasses that unlock items (checked every join, and granted right after an in-game purchase)
	GamePasses={
		VIP={Id=2017910251,Name="VIP Flashlight",Grants={{"Flashlight","VIP"},{"Beam","VIP"},{"Title","VIP"}}},
	},
	-- items that were renamed; older saves are read with the new names
	Renamed={["Flashlight:Rune"]="Flashlight:Phantom",["Flashlight:Rustbelt"]="Flashlight:Default"},
	-- how close (studs) a player must be to take a collectible
	ClaimDistance=9,
})
