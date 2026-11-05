--!strict
-- Lobby tip jar + leaderboards (Oct 18). Keep identical in the Lobby and Game places.
-- The nine tips are Developer Products bought in the lobby; the Game place only reads the boards to
-- give the same chat tags, and shows tip announcements from every server.
local Freeze=require(script.Parent.Parent.Utilities.TableUtil).DeepFreeze
return Freeze({
	Tips={
		{Robux=5,ProductId=3719686186},
		{Robux=25,ProductId=3719687929},
		{Robux=50,ProductId=3719688795},
		{Robux=100,ProductId=3719689024},
		{Robux=250,ProductId=3719689392},
		{Robux=750,ProductId=3719689710},
		{Robux=1500,ProductId=3719689991},
		{Robux=5000,ProductId=3719690543},
		{Robux=10000,ProductId=3719690725},
	},
	DonationStore="EHDonationsV1",
	DonationBoard="EHDonorBoardV1",
	CoinBoard="EHCoinBoardV1",
	BoardSize=100,
	RefreshSeconds=60,
	DonorColor="#5ED27A",
	CoinColor="#F2C14E",
	TipColor="#5ED27A",
})
