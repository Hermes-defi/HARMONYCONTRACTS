/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('dotenv').config({path: '.env'});
require('hardhat/types');
require('hardhat-deploy');
require('hardhat-deploy-ethers');

// import 'hardhat-gas-reporter';
// import 'hardhat-spdx-license-identifier';
// import 'hardhat-contract-sizer';
// import '@nomiclabs/hardhat-etherscan';


export default config = {
  solidity: {
    compilers: [
      {
        version: '0.6.12',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      blockGasLimit: 12_450_000,
      hardfork: "london"
    },
    localhost: {
      url: 'http://localhost:8545',
    },
  },
  paths: {
    sources: 'contracts',
  },
  mocha: {
    timeout: 0,
  },
};

