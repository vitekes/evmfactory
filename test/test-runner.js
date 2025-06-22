const { spawn } = require('child_process');
const path = require('path');

// Path to local Hardhat binary for cross-platform support
const bin = path.resolve(__dirname, '../node_modules/.bin/hardhat');
const cmd = process.platform === 'win32' ? `${bin}.cmd` : bin;

const args = ['test', ...process.argv.slice(2)];

const child = spawn(cmd, args, { stdio: 'inherit' });
child.on('exit', code => process.exit(code ?? 1));

