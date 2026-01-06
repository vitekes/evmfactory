import { ethers } from '../../hardhat-connection';
import type { Signer } from 'ethers';
import type { PaymentGateway } from '../../typechain-types';

export async function authorizeModule(gatewayAddress: string, moduleId: string, moduleAddress: string, signer: Signer) {
  const gateway = (await ethers.getContractAt('PaymentGateway', gatewayAddress, signer)) as PaymentGateway;
  await (await gateway.setModuleAuthorization(moduleId, moduleAddress, true)).wait();
}
