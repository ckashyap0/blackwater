--!strict
-- Lobby tip jar + leaderboards (Oct 18). The nine tips are Developer Products; CoinService owns
-- ProcessReceipt and routes them to LeaderboardService. Gamepasses never count toward the board.
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
	DonationStore="EHDonationsV1",   -- U_<userId> -> {total=n, receipts={[purchaseId]=time}}
	DonationBoard="EHDonorBoardV1",  -- ordered: userId -> total Robux tipped
	CoinBoard="EHCoinBoardV1",       -- ordered: userId -> current coin balance
	BoardSize=100,
	RefreshSeconds=30,
	-- chat tags: ranks 1-10 get their own number, 11-100 the Top 100 tag; dropping out removes it
	DonorColor="#5ED27A",
	CoinColor="#F2C14E",
	TipColor="#5ED27A",
})
