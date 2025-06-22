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
if (!fs.existsSync(cliPath)) {
    console.log('Hardhat CLI not found. Installing dependencies...');
    const install = spawnSync('npm', ['install'], { stdio: 'inherit' });
    if (install.status !== 0) {
        console.error('Failed to install dependencies.');
        process.exit(1);
    }
}

if (fs.existsSync(cliPath)) {
    result = spawnSync(process.execPath, [cliPath, ...args], { stdio: 'inherit' });
} else {
    console.error('Hardhat CLI still missing after install.');
    process.exit(1);
}

if (result.error) {
    console.error('Failed to run hardhat tests:', result.error);
}

process.exit(result.status ?? 1);
