import { ethers } from "hardhat";
import { PrizeType } from "./constants";
import { getAddressFromEvents } from "./helpers";

export interface PrizeInfo {
  prizeType: PrizeType;
  token: string;
  amount: bigint;
  distribution: number;
  uri: string;
}

/**
 * Deploys a contest via ContestFactory and returns the escrow address
 */
export async function createContest(
  factory: any,
  token: string,
  metadata: string = "0x"
): Promise<string> {
  const prizes: PrizeInfo[] = [
    {
      prizeType: PrizeType.MONETARY,
      token,
      amount: ethers.parseEther("10"),
      distribution: 0,
      uri: ""
    },
    {
      prizeType: PrizeType.MONETARY,
      token,
      amount: ethers.parseEther("5"),
      distribution: 0,
      uri: ""
    },
    {
      prizeType: PrizeType.PROMO,
      token: ethers.ZeroAddress,
      amount: 0n,
      distribution: 0,
      uri: "ipfs://promo_reward"
    }
  ];

  const tx = await factory.createContest(prizes, metadata);
  const receipt = await tx.wait();
  const contestAddr = getAddressFromEvents(
    receipt,
    "ContestCreated",
    "ContestCreated(address,address,uint256)",
    1
  );
  if (!contestAddr) {
    throw new Error("contest address not found");
  }
  return contestAddr;
}

/**
 * Finalizes a contest and distributes prizes
 */
export async function finalizeContest(
  contestAddress: string,
  winners: string[]
): Promise<void> {
  const escrow = await ethers.getContractAt("ContestEscrow", contestAddress);
  const tx = await escrow.finalize(winners, 0n, 0n);
  await tx.wait();
}
