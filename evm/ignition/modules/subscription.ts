import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';

export const SubscriptionModule = buildModule('SubscriptionModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const { gateway, orchestrator } = m.useModule(PaymentStackModule);

  const subscriptionModuleId = ethers.id('SubscriptionManager');
  const allowedTokens = m.getParameter('subscriptionAllowedTokens', [] as string[]);

  const subscriptionManager = m.contract('SubscriptionManager', [core, gateway, subscriptionModuleId]);

  const registerSubscription = m.call(core, 'registerFeature', [subscriptionModuleId, subscriptionManager, 0], {
    id: 'SubscriptionModule_registerFeature',
  });

  const setPaymentGateway = m.call(core, 'setService', [subscriptionModuleId, 'PaymentGateway', gateway], {
    id: 'SubscriptionModule_setPaymentGateway',
    after: [registerSubscription],
  });

  m.call(gateway, 'setModuleAuthorization', [subscriptionModuleId, subscriptionManager, true], {
    id: 'SubscriptionModule_authorizeGateway',
    after: [setPaymentGateway],
  });

  m.call(
    orchestrator,
    'configureProcessor',
    [subscriptionModuleId, 'FeeProcessor', true, '0x'],
    { id: 'SubscriptionModule_configureFeeProcessor', after: [setPaymentGateway] },
  );

  const tokenFilterEnabled = allowedTokens.length > 0;
  const tokenFilterConfig = tokenFilterEnabled
    ? ethers.concat(allowedTokens.map((addr) => ethers.getBytes(addr)))
    : '0x';

  m.call(
    orchestrator,
    'configureProcessor',
    [subscriptionModuleId, 'TokenFilter', tokenFilterEnabled, tokenFilterConfig],
    { id: 'SubscriptionModule_configureTokenFilter', after: [setPaymentGateway] },
  );

  return {
    subscriptionManager,
  };
});

export default SubscriptionModule;
