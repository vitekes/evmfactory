import type { ContractTransactionReceipt } from 'ethers';
import type { PaymentGateway } from '../../typechain-types';
import { log } from './logging';

export interface PaymentProcessedEvent {
  moduleId: string;
  paymentId: string;
  token: string;
  payer: string;
  amount: bigint;
  netAmount: bigint;
  status: number;
}

export function parsePaymentProcessed(
  receipt: ContractTransactionReceipt | null | undefined,
  gateway: PaymentGateway
): PaymentProcessedEvent | null {
  if (!receipt) {
    return null;
  }

  for (const entry of receipt.logs) {
    try {
      const parsed = gateway.interface.parseLog(entry);
      if (parsed && parsed.name === 'PaymentProcessed') {
        return {
          moduleId: parsed.args.moduleId as string,
          paymentId: parsed.args.paymentId as string,
          token: parsed.args.token as string,
          payer: parsed.args.payer as string,
          amount: parsed.args.amount as bigint,
          netAmount: parsed.args.netAmount as bigint,
          status: Number(parsed.args.status),
        };
      }
    } catch {
      // ignore unrelated log
    }
  }

  return null;
}

export function logPaymentProcessed(event: PaymentProcessedEvent | null) {
  if (!event) {
    log.warn('PaymentProcessed event not found in transaction logs.');
    return;
  }

  const formattedAmount = event.amount.toString();
  const formattedNet = event.netAmount.toString();
  log.success(
    `PaymentProcessed: module=${event.moduleId}, payer=${event.payer}, amount=${formattedAmount}, net=${formattedNet}, status=${event.status}`
  );
}
