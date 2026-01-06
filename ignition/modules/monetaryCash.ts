import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';
import { ethers } from 'ethers';
import { CoreSystemModule } from './core';

export const MonetaryCashModule = buildModule('MonetaryCashModule', (m) => {
  const { core } = m.useModule(CoreSystemModule);
  const moduleId = ethers.id('MonetaryCash');
  const backendSigner = m.getParameter('monetaryBackendSigner', m.getAccount(0));

  const monetaryCash = m.contract('MonetaryCash', [core, moduleId, backendSigner]);

  m.call(core, 'registerFeature', [moduleId, monetaryCash, 0], {
    id: 'MonetaryCash_registerFeature',
  });

  return { monetaryCash };
});

export default MonetaryCashModule;
