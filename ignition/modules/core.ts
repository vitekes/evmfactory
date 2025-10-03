import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export const CoreSystemModule = buildModule('CoreSystemModule', (m) => {
  const admin = m.getAccount(0);
  const automationAccount = m.getParameter('automationAccount', admin);

  const core = m.contract('CoreSystem', [admin]);

  const featureOwnerRole = m.staticCall(core, 'FEATURE_OWNER_ROLE', []);
  m.call(core, 'grantRole', [featureOwnerRole, admin], { id: 'CoreSystemModule_grantFeatureOwner' });

  const automationRole = m.staticCall(core, 'AUTOMATION_ROLE', []);
  m.call(core, 'grantRole', [automationRole, automationAccount], { id: 'CoreSystemModule_grantAutomation' });

  return {
    core,
    admin,
    automationAccount,
  };
});

export default CoreSystemModule;

