require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-web3");

const dotenv = require('dotenv');
dotenv.config();

const privateKey = process.env.DEPLOY_ACCOUNT_PRIVATE_KEY;

const projectIdKey = process.env.PROJECT_KEY;

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: "0.8.9",
  networks: {
    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${projectIdKey}`, //Infura url with projectId
      accounts: [privateKey] // add the account that will deploy the contract (private key)
    },
    kovan: {
      url: `https://kovan.infura.io/v3/5e34fc08bb504544a874172303d2a0fb`, //Infura url with projectId
      accounts: [privateKey] // add the account that will deploy the contract (private key)
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_KEY,
  }
};
