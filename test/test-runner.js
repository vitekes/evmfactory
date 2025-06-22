// test/test-runner.js

const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

// Путь к локальному бинарнику Hardhat для кросс-платформенности
const binPath = path.resolve(
    __dirname,
    '../node_modules/.bin/hardhat' + (process.platform === 'win32' ? '.cmd' : '')
);

const args = ['test', ...process.argv.slice(2)];

let result;
if (fs.existsSync(binPath)) {
    result = spawnSync(binPath, args, { stdio: 'inherit' });
} else {
    const npxCmd = process.platform === 'win32' ? 'npx.cmd' : 'npx';
    result = spawnSync(npxCmd, ['hardhat', ...args], { stdio: 'inherit' });
}

if (result.error) {
    console.error('Failed to run hardhat tests:', result.error);
}

process.exit(result.status ?? 1);
