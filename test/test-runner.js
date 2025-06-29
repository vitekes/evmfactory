#!/usr/bin/env node

const { spawnSync } = require('child_process');
const path = require('path');

function run(cmd, args) {
  const result = spawnSync(cmd, args, { stdio: 'inherit' });
  if (result.error) {
    console.error(result.error);
  }
  return result.status ?? 1;
}

function hardhat(args) {
  const bin = path.resolve(__dirname, '../node_modules/.bin/hardhat' + (process.platform === 'win32' ? '.cmd' : ''));
  return run(bin, args);
}

function forge(args) {
  const cmd = process.platform === 'win32' ? 'forge.exe' : 'forge';
  return run(cmd, args);
}

function help() {
  console.log(`Usage: node test/test-runner.js <task>

Tasks:
  unit         Run Forge unit tests
  integration  Run Hardhat JS tests
  e2e          Alias for integration
  all          Run both Forge and Hardhat tests
  coverage     Run coverage for Forge and Hardhat (uses --ir-minimum for Forge)
  quick        Alias for unit
  --help       Show this help
`);
}

function main() {
  const task = process.argv[2];
  let code = 0;
  switch (task) {
    case 'unit':
    case 'quick':
      code = forge(['test', '-vv']);
      break;
    case 'integration':
    case 'e2e':
      code = hardhat(['test']);
      break;
    case 'all':
      code |= forge(['test', '-vv']);
      code |= hardhat(['test']);
      break;
    case 'coverage':
      code |= forge(['coverage', '--report', 'lcov', '--ir-minimum']);
      code |= run('npm', ['run', 'coverage']);
      break;
    default:
      help();
      return 0;
  }
  return code;
}

process.exitCode = main();
