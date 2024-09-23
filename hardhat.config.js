require("@nomicfoundation/hardhat-toolbox");


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.27",

  networks: {
    hardhat: {
      forking: {
        url: "https://arbitrum-one-rpc.publicnode.com"
      },
    },
  },
  mocha: {
    timeout: 100000000
  },

};
