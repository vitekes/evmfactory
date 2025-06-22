// test/test-runner.js

const { spawn } = require('child_process');
const path = require('path');

// Путь к локальному бинарнику Hardhat для кросс-платформенности
const bin = path.resolve(__dirname, '../node_modules/.bin/hardhat');
const cmd = process.platform === 'win32' ? `${bin}.cmd` : bin;

const args = ['test', ...process.argv.slice(2)];

const child = spawn(cmd, args, { stdio: 'inherit' });

child.on('error', err => {
    console.error('Failed to run hardhat tests:', err);
    process.exit(1);
});

child.on('exit', code => process.exit(code ?? 1));
