require('dotenv').config({path: '/media/veracrypt1/bitdeep/.env'});
const HDWalletProvider = require('@truffle/hdwallet-provider');
const fs = require('fs');
const mnemonic = fs.readFileSync("/media/veracrypt1/bitdeep/seed-mainnet").toString().trim();
module.exports = {
    networks: {
        dev: {
            host: "127.0.0.1",
            port: 7545,
            network_id: "*"
        },
        mainnet: {
            provider: () => new HDWalletProvider(
                {
                    mnemonic: mnemonic,
                    providerOrUrl: `https://api.s0.t.hmny.io/`,
                    chainId: 1666600000
                }),
            network_id: 1666600000,
            confirmations: 3,
            timeoutBlocks: 200,
            skipDryRun: true
        },
    },
    compilers: {
        solc: {
            version: "0.6.12",
            settings: {
                optimizer: {
                    enabled: true,
                    runs: 200
                }
            }
        }
    },
    plugins: [
        'truffle-plugin-verify'
    ],
    api_keys: {
        bscscan: process.env.bscscan,
        etherscan: process.env.etherscan
    },
    mocha: {
        enableTimeouts: false,
        before_timeout: 120000
    }
};
