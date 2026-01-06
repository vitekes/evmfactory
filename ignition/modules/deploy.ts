import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';
import { ContestModule } from './contest';
import { SubscriptionModule } from './subscription';
import { MarketplaceModule } from './marketplace';
import { DonateModule } from './donate';
import { MonetaryCashModule } from './monetaryCash';

const DeploymentModule = buildModule('DeploymentModule', (m) => {
  const core = m.useModule(CoreSystemModule);
  const payment = m.useModule(PaymentStackModule);
  const contest = m.useModule(ContestModule);
  const subscription = m.useModule(SubscriptionModule);
  const marketplace = m.useModule(MarketplaceModule);
  const donate = m.useModule(DonateModule);
  const monetaryCash = m.useModule(MonetaryCashModule);

  return {
    core: core.core,
    paymentRegistry: payment.registry,
    paymentOrchestrator: payment.orchestrator,
    paymentGateway: payment.gateway,
    paymentTokenFilter: payment.tokenFilter,
    paymentFeeProcessor: payment.feeProcessor,
    contestFactory: contest.contestFactory,
    subscriptionManager: subscription.subscriptionManager,
    planManager: subscription.planManager,
    marketplace: marketplace.marketplace,
    donate: donate.donate,
    monetaryCash: monetaryCash.monetaryCash,
  };
});

export default DeploymentModule;
