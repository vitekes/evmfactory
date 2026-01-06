import { network } from "hardhat";

export const connection = await network.connect();
export const { ethers, ignition } = connection;
export const networkName = connection.networkName;
export const provider = connection.provider;
