// test/test-runner.js

const { spawnSync } = require('child_process');

// на Windows нужно «npm.cmd», на *nix — «npm»
const npmCmd = process.platform === 'win32' ? 'npm.cmd' : 'npm';

// запускаем определённый в package.json скрипт test:hardhat
const result = spawnSync(npmCmd, ['run', 'test:hardhat'], { stdio: 'inherit' });

if (result.error) {
    console.error('Failed to run hardhat tests:', result.error);
    process.exit(1);
}

process.exit(result.status === null ? 1 : result.status);
