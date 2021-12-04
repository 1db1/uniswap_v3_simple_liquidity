async function main() {
      const [deployer] = await ethers.getSigners();

      console.log("Deploying contracts with the account:", deployer.address);

      console.log("Account balance:", (await deployer.getBalance()).toString());

      const UniswapV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
      const NonfungiblePositionManager = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
      const SwapRouter = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
      const WETH_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

      const SimpleLiquidity = await ethers.getContractFactory("SimpleLiquidity");
      const simpleLiquidity = await SimpleLiquidity.deploy(UniswapV3Factory, WETH_address, NonfungiblePositionManager, SwapRouter);

      console.log("SimpleLiquidity address:", simpleLiquidity.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
          console.error(error);
          process.exit(1);
        });

