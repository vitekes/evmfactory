import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';

export const ContestModule = buildModule('ContestModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const { gateway, orchestrator } = m.useModule(PaymentStackModule);

  const contestModuleId = ethers.id('Contest');
  const allowedTokens = m.getParameter('contestAllowedTokens', [ethers.ZeroAddress] as string[]);

  const contestFactory = m.contract('ContestFactory', [core, gateway]);

  const registerContest = m.call(core, 'registerFeature', [contestModuleId, contestFactory, 0], {
    id: 'ContestModule_registerFeature',
  });

  m.call(core, 'setService', [contestModuleId, 'PaymentGateway', gateway], {
    id: 'ContestModule_setPaymentGateway',
    after: [registerContest],
  });

  const feeConfig = m.call(
    orchestrator,
    'configureProcessor',
    [contestModuleId, 'FeeProcessor', true, '0x'],
    { id: 'ContestModule_configureFeeProcessor', after: [registerContest] },
  );

  const tokenFilterEnabled = allowedTokens.length > 0;
  const tokenFilterConfig = tokenFilterEnabled
    ? ethers.concat(allowedTokens.map((addr) => ethers.getBytes(addr)))
    : '0x';

  m.call(
    orchestrator,
    'configureProcessor',
    [contestModuleId, 'TokenFilter', tokenFilterEnabled, tokenFilterConfig],
    { id: 'ContestModule_configureTokenFilter', after: [feeConfig] },
  );

  return {
    contestFactory,
  };
});

export default ContestModule;
