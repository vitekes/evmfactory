import { ethers } from 'hardhat';
import type { Signer } from 'ethers';
import type { Donate, PaymentOrchestrator } from '../../typechain-types';
import { log } from './logging';

export interface DonationEventData {
  donationId: bigint;
  donor: string;
  recipient: string;
  token: string;
  grossAmount: bigint;
  netAmount: bigint;
  metadata: string;
  timestamp: bigint;
  moduleId: string;
}

export async function configureDonationProcessors(
  orchestrator: PaymentOrchestrator,
  moduleId: string,
  allowedTokens: string[],
  feeRecipient: string,
  feeBps: number
) {
  const feePercentBytes = ethers.zeroPadValue(ethers.toBeHex(feeBps), 2);
  const feeRecipientBytes = ethers.zeroPadValue(feeRecipient, 20);
  const feeConfig = ethers.concat([feePercentBytes, feeRecipientBytes]);

  await (
    await orchestrator.configureProcessor(moduleId, 'FeeProcessor', true, feeConfig)
  ).wait();

  const tokenConfig =
    allowedTokens.length > 0 ? ethers.concat(allowedTokens.map((addr) => ethers.getBytes(addr))) : '0x';
  await (
    await orchestrator.configureProcessor(moduleId, 'TokenFilter', true, tokenConfig)
  ).wait();

  log.success('Donation processors configured (FeeProcessor & TokenFilter).');
}

export async function submitDonation(
  donate: Donate,
  donor: Signer,
  recipient: string,
  token: string,
  amount: bigint,
  metadata: string
): Promise<DonationEventData | null> {
  log.info(`Submitting donation of ${amount.toString()} units to ${recipient}...`);
  const tx = await donate.connect(donor).donate(recipient, token, amount, metadata);
  const receipt = await tx.wait();
  log.success('Donation transaction confirmed.');

  for (const entry of receipt.logs) {
    try {
      const parsed = donate.interface.parseLog(entry);
      if (parsed.name === 'DonationProcessed') {
        const event: DonationEventData = {
          donationId: parsed.args.donationId as bigint,
          donor: parsed.args.donor as string,
          recipient: parsed.args.recipient as string,
          token: parsed.args.token as string,
          grossAmount: parsed.args.grossAmount as bigint,
          netAmount: parsed.args.netAmount as bigint,
          metadata: parsed.args.metadata as string,
          timestamp: parsed.args.timestamp as bigint,
          moduleId: parsed.args.moduleId as string,
        };
        log.success(
          `DonationProcessed: donor=${event.donor}, recipient=${event.recipient}, token=${event.token}, gross=${event.grossAmount.toString()}, net=${event.netAmount.toString()}`
        );
        return event;
      }
    } catch {
      // ignore unrelated logs
    }
  }

  log.warn('DonationProcessed event not found in transaction logs.');
  return null;
}
