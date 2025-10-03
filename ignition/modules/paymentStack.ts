import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export const PaymentStackModule = buildModule('PaymentStackModule', (m) => {
  const defaultFeeBps = m.getParameter('defaultFeeBps', 250);

  const registry = m.contract('ProcessorRegistry', []);
  const orchestrator = m.contract('PaymentOrchestrator', [registry]);
  const gateway = m.contract('PaymentGateway', [orchestrator]);

  const tokenFilter = m.contract('TokenFilterProcessor', []);
  const feeProcessor = m.contract('FeeProcessor', [defaultFeeBps]);

  const registerTokenFilter = m.call(
    registry,
    'registerProcessor',
    [tokenFilter, 0],
    { id: 'PaymentStack_registerTokenFilter' },
  );

  const registerFeeProcessor = m.call(
    registry,
    'registerProcessor',
    [feeProcessor, 1],
    { id: 'PaymentStack_registerFeeProcessor', after: [registerTokenFilter] },
  );

  const tokenFilterAdminRole = m.staticCall(tokenFilter, 'PROCESSOR_ADMIN_ROLE', []);
  m.call(
    tokenFilter,
    'grantRole',
    [tokenFilterAdminRole, orchestrator],
    { id: 'PaymentStack_grantTokenFilterAdmin', after: [registerFeeProcessor] },
  );

  const feeProcessorAdminRole = m.staticCall(feeProcessor, 'PROCESSOR_ADMIN_ROLE', []);
  m.call(
    feeProcessor,
    'grantRole',
    [feeProcessorAdminRole, orchestrator],
    { id: 'PaymentStack_grantFeeProcessorAdmin', after: [registerFeeProcessor] },
  );

  return {
    registry,
    orchestrator,
    gateway,
    tokenFilter,
    feeProcessor,
  };
});

export default PaymentStackModule;
