const { execSync } = require('child_process');
execSync('npx hardhat test', { stdio: 'inherit' });
