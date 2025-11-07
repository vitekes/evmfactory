import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';

export const SubscriptionModule = buildModule('SubscriptionModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const { gateway, orchestrator } = m.useModule(PaymentStackModule);

  const subscriptionModuleId = ethers.id('SubscriptionManager');
  const allowedTokens = m.getParameter('subscriptionAllowedTokens', [] as string[]);
  const maxActivePlans = m.getParameter('subscriptionMaxActivePlans', 5);
  const authorAccountsParam = m.getParameter('subscriptionAuthors', [] as string[]);
  const automationAccountsParam = m.getParameter('subscriptionAutomation', [] as string[]);

  const toAccountArray = (value: unknown): string[] => {
    if (Array.isArray(value)) {
      return value.filter((item): item is string => typeof item === 'string' && item.length > 0);
    }
    if (typeof value === 'string' && value.length > 0) {
      return [value];
    }
    return [];
  };

  const authorAccounts = toAccountArray(authorAccountsParam);
  const automationAccounts = toAccountArray(automationAccountsParam);

  const subscriptionManager = m.contract('SubscriptionManager', [core, gateway, subscriptionModuleId]);
  const planManager = m.contract('PlanManager', [core, subscriptionManager, subscriptionModuleId, maxActivePlans]);

  const registerSubscription = m.call(core, 'registerFeature', [subscriptionModuleId, subscriptionManager, 0], {
    id: 'SubscriptionModule_registerFeature',
  });

  const setPaymentGateway = m.call(core, 'setService', [subscriptionModuleId, 'PaymentGateway', gateway], {
    id: 'SubscriptionModule_setPaymentGateway',
    after: [registerSubscription],
  });

  const setPlanManager = m.call(core, 'setService', [subscriptionModuleId, 'PlanManager', planManager], {
    id: 'SubscriptionModule_setPlanManager',
    after: [registerSubscription],
  });

  const authorRoleCalls = authorAccounts.map((account, index) =>
    m.call(core, 'grantRole', [ethers.id('AUTHOR_ROLE'), account], {
      id: `SubscriptionModule_grantAuthor_${index}`,
      after: [registerSubscription],
    }),
  );

  const automationRoleCalls = automationAccounts.map((account, index) =>
    m.call(core, 'grantRole', [ethers.id('AUTOMATION_ROLE'), account], {
      id: `SubscriptionModule_grantAutomation_${index}`,
      after: [registerSubscription],
    }),
  );

  const operatorRoleCall = m.call(core, 'grantRole', [ethers.id('OPERATOR_ROLE'), subscriptionManager], {
    id: 'SubscriptionModule_grantOperator',
    after: [registerSubscription],
  });

  m.call(gateway, 'setModuleAuthorization', [subscriptionModuleId, subscriptionManager, true], {
    id: 'SubscriptionModule_authorizeGateway',
    after: [setPaymentGateway, setPlanManager],
  });

  m.call(
    orchestrator,
    'configureProcessor',
    [subscriptionModuleId, 'FeeProcessor', true, '0x'],
    { id: 'SubscriptionModule_configureFeeProcessor', after: [setPaymentGateway, setPlanManager] },
  );

  const tokenFilterEnabled = allowedTokens.length > 0;
  const tokenFilterConfig = tokenFilterEnabled
    ? ethers.concat(allowedTokens.map((addr) => ethers.getBytes(addr)))
    : '0x';

  m.call(
    orchestrator,
    'configureProcessor',
    [subscriptionModuleId, 'TokenFilter', tokenFilterEnabled, tokenFilterConfig],
    { id: 'SubscriptionModule_configureTokenFilter', after: [setPaymentGateway, setPlanManager] },
  );

  return {
    subscriptionManager,
    planManager,
    authorRoleCalls,
    automationRoleCalls,
    operatorRoleCall,
  };
});

export default SubscriptionModule;
