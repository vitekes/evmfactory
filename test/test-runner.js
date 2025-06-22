// test/test-runner.js

const { spawnSync } = require('child_process');

// на Windows нужно «npm.cmd», на *nix — «npm»
const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';

// запускаем определённый в package.json скрипт test:hardhat
const result = spawnSync(
    npmCmd,
    ['run', 'test:hardhat'],
    { stdio: 'inherit' }
);

process.exit(result.status);
