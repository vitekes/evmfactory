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
    console.error('Hardhat binary not found. Did you run "npm install"?');
    process.exit(1);
}

if (result.error) {
    console.error('Failed to run hardhat tests:', result.error);
}

process.exit(result.status ?? 1);
