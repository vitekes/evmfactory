import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';
import { ContestModule } from './contest';
import { SubscriptionModule } from './subscription';

const DeploymentModule = buildModule('DeploymentModule', (m) => {
  const core = m.useModule(CoreSystemModule);
  const payment = m.useModule(PaymentStackModule);
  const contest = m.useModule(ContestModule);
  const subscription = m.useModule(SubscriptionModule);

  return {
    core: core.core,
    paymentRegistry: payment.registry,
    paymentOrchestrator: payment.orchestrator,
    paymentGateway: payment.gateway,
    paymentTokenFilter: payment.tokenFilter,
    paymentFeeProcessor: payment.feeProcessor,
    contestFactory: contest.contestFactory,
    subscriptionManager: subscription.subscriptionManager,
  };
});

export default DeploymentModule;
