import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';

export const DonateModule = buildModule('DonateModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const { gateway, orchestrator } = m.useModule(PaymentStackModule);

  const donateModuleId = ethers.id('Donate');
  const usdc = ethers.getAddress('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');
  const usdt = ethers.getAddress('0xdAC17F958D2ee523a2206206994597C13D831ec7');
  const allowedTokens = m.getParameter('donateAllowedTokens', [usdc, usdt] as string[]);

  const donate = m.contract('Donate', [core, gateway, donateModuleId]);

  const registerDonate = m.call(core, 'registerFeature', [donateModuleId, donate, 0], {
    id: 'DonateModule_registerFeature',
  });

  const setPaymentGateway = m.call(core, 'setService', [donateModuleId, 'PaymentGateway', gateway], {
    id: 'DonateModule_setPaymentGateway',
    after: [registerDonate],
  });

  m.call(gateway, 'setModuleAuthorization', [donateModuleId, donate, true], {
    id: 'DonateModule_setModuleAuthorization',
    after: [registerDonate, setPaymentGateway],
  });

  m.call(
    orchestrator,
    'configureProcessor',
    [donateModuleId, 'FeeProcessor', true, '0x'],
    { id: 'DonateModule_configureFeeProcessor', after: [setPaymentGateway] }
  );

  const tokenFilterEnabled = allowedTokens.length > 0;
  const tokenFilterConfig = tokenFilterEnabled
    ? ethers.concat(allowedTokens.map((addr) => ethers.getBytes(addr)))
    : '0x';

  m.call(
    orchestrator,
    'configureProcessor',
    [donateModuleId, 'TokenFilter', tokenFilterEnabled, tokenFilterConfig],
    { id: 'DonateModule_configureTokenFilter', after: [setPaymentGateway] }
  );

  return {
    donate,
  };
});

export default DonateModule;
