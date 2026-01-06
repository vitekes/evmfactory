
import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';
import { PaymentStackModule } from './paymentStack';

export const MarketplaceModule = buildModule('MarketplaceModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const { gateway } = m.useModule(PaymentStackModule);

  const marketplaceModuleId = ethers.id('Marketplace');

  const marketplace = m.contract('Marketplace', [core, gateway, marketplaceModuleId]);

  const registerMarketplace = m.call(core, 'registerFeature', [marketplaceModuleId, marketplace, 0], {
    id: 'MarketplaceModule_registerFeature',
  });

  m.call(core, 'setService', [marketplaceModuleId, 'PaymentGateway', gateway], {
    id: 'MarketplaceModule_setPaymentGateway',
    after: [registerMarketplace],
  });

  m.call(gateway, 'setModuleAuthorization', [marketplaceModuleId, marketplace, true], {
    id: 'MarketplaceModule_setModuleAuthorization',
    after: [registerMarketplace],
  });

  return {
    marketplace,
  };
});

export default MarketplaceModule;
