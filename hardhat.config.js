require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
const UNISWAP_SETTING = {
  version: '0.7.6',
  settings: {
    optimizer: {
      enabled: true,
      runs: 800,
    }
  }
}

module.exports = {
	solidity:	{
		compilers: [
			{
				version: '0.8.4',
				settings: {
				  optimizer: {
					enabled: true,
					runs: 2000,
				  }
				}
			},
      UNISWAP_SETTING
		],
		overrides: {
			'@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol': UNISWAP_SETTING,
		}
	},
	networks: {
	  hardhat: {
		forking: {
		  url: "https://eth-mainnet.alchemyapi.io/v2/<alchemy key>,
		  blockNumber:  13645986 
		},
        //loggingEnabled: true
	  },
      kovan: {
          url: `https://kovan.infura.io/v3/<infura key>`,
          accounts: [`<private key>`]
      }
	},
	etherscan: {
		apiKey: "<etherscan key>"
	}
}

