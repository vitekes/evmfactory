# Demo Scenarios

������� ������������� �������, �������� � ��������. ���� ������ �� ������, Ignition ������������� �������� ���� (core + payment + ������) � �������� �� � demo/.deployment.json.

## ����������

1. (�����������) ����������� ������� ����� ����������:
   `ash
   npx hardhat ignition deploy ignition/modules/deploy.ts --network hardhat --parameters ignition/parameters/dev.ts
   `
2. ��� �������� ������� ������������ �� � .env.demo (��� �������������� cache-����):
   `env
   DEMO_CORE=0x...
   DEMO_PAYMENT_GATEWAY=0x...
   DEMO_PR_REGISTRY=0x...
   DEMO_CONTEST_FACTORY=0x...
   DEMO_SUBSCRIPTION_MANAGER=0x...
   DEMO_TEST_TOKEN=0x...
   `

## ������� �����

`ash
npm run demo:payment
npm run demo:subscription
npm run demo:contest
`

������ ��������:
- ��� ������������� ������������� TestToken � ������� �����������;
- �������� �������� ���� ([INFO], [OK], [WARN]);
- ��������� ���������� ��� ������ ����.

## ���������

`
demo/
  README.md
  .env.example
  config/
    addresses.ts
  utils/
    logging.ts
    signers.ts
    tokens.ts
    gateway.ts
    core.ts
  scenarios/
    run-payment-scenario.ts
    run-subscription-scenario.ts
    run-contest-scenario.ts
`

ignition/parameters/ �������� ��������� ��� dev/prod ������ (��������� ����� �������������� ������ --parameters).

