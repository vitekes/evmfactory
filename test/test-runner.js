// test/test-runner.js

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Путь к локальному cli Hardhat для кросс-платформенности
const cliPath = path.resolve(
    __dirname,
    '../node_modules/hardhat/internal/cli/cli.js'
);

const args = ['test', ...process.argv.slice(2)];

let result;
if (fs.existsSync(cliPath)) {
    result = spawnSync(process.execPath, [cliPath, ...args], { stdio: 'inherit' });
} else {
    console.error('Hardhat CLI not found. Did you run "npm install"?');
    process.exit(1);
}

if (result.error) {
    console.error('Failed to run hardhat tests:', result.error);
}

process.exit(result.status ?? 1);
