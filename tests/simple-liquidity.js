const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("SimpleLiquidity contract", function () {
    const provider = ethers.getDefaultProvider("http://127.0.0.1:8545");
    const IERC20 = [
        "function deposit() public payable",
        "function balanceOf(address) view returns (uint256)",
        "function decimals() view returns (uint8)",
        "function transfer(address to, uint amount) returns (bool)",
        "function approve(address spender, uint256 amount) returns (bool)"
    ]
    const WETH_address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    const USDC_address = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

    const UniswapV3Factory = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
    const NonfungiblePositionManager = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
    const SwapRouter = '0xE592427A0AEce92De3Edee1F18E0157C05861564';

    const UniV2_router_address = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
    const UniV2_router_ABI = [
        "function swapExactETHForTokens(uint256,address[],address,uint256) payable returns (uint256[])"
    ]
    const NonfungiblePositionManager_ABI = [
        "function tokenByIndex(uint256) external view returns (uint256)",
        "function tokenOfOwnerByIndex(address, uint256) external view returns (uint256)",
        "function positions(uint256) external view returns (uint96,address,address,address,uint24,int24,int24,uint128,uint256,uint256,uint128,uint128)"
    ]

    let signer;
	let signerAddress;
	let SimpleLiquidityFactory;
	let simpleLiquidity;
    let WETH;
    let UniV2_router;
    let tokenIndex = 0;
    let positionManager;

	beforeEach(async function () {
	    [signer] = await ethers.getSigners();
        signerAddress = await signer.getAddress();
        SimpleLiquidity = await ethers.getContractFactory("SimpleLiquidity");
        simpleLiquidity = await SimpleLiquidity.deploy(UniswapV3Factory, WETH_address, NonfungiblePositionManager, SwapRouter);
        simpleLiquidity.deployed();
        positionManager = new ethers.Contract(NonfungiblePositionManager, NonfungiblePositionManager_ABI, signer);

        WETH = new ethers.Contract(WETH_address, IERC20, signer);

        UniV2_router = new ethers.Contract(UniV2_router_address, UniV2_router_ABI, signer);

        // Swap ETH -> WETH
        let params = { to: WETH.address, value: ethers.utils.parseUnits("10", "ether").toHexString()};
        let result = await signer.sendTransaction(params);
	});

    describe("Deployment", function () {
      it("Adding liquidity without token0 approving", async function () {
        const USDC = new ethers.Contract(USDC_address, IERC20, signer);

        await expect(
            simpleLiquidity.newPosition({
                token0: WETH_address,
                token1: USDC_address,
                amount0: ethers.utils.parseUnits("0.5", "ether").toHexString(),
                amount1: ethers.utils.parseUnits("1000.0", 6).toHexString(),
                feeTier: 3000,
                tickLower: 170000,
                tickUpper: 200000,
                slippage: 10
            })
        ).to.be.reverted;
      });

      it("Adding liquidity without token1 approving", async function () {
        const USDC = new ethers.Contract(USDC_address, IERC20, signer);

        // approving token0
        await WETH.approve(simpleLiquidity.address, ethers.utils.parseUnits("0.5", "ether").toHexString());

        await expect(
            simpleLiquidity.newPosition({
                token0: WETH_address,
                token1: USDC_address,
                amount0: ethers.utils.parseUnits("0.5", "ether").toHexString(),
                amount1: ethers.utils.parseUnits("1000.0", 6).toHexString(),
                feeTier: 3000,
                tickLower: 170000,
                tickUpper: 200000,
                slippage: 10
            })
        ).to.be.reverted;
      });

      it("New liquidity position 0.5 WETH + 1000 USDC ", async function () {
        const token0 = new ethers.Contract(WETH_address, IERC20, signer);
        const token1 = new ethers.Contract(USDC_address, IERC20, signer);

        const amount0 = ethers.utils.parseUnits("0.5", await token0.decimals()).toHexString();
        const amount1 = ethers.utils.parseUnits("1000.0", await token1.decimals()).toHexString();
        const feeTier = 3000;

        // Swap ETH -> token1
        result = await UniV2_router.swapExactETHForTokens(
            100, 
            [WETH_address, token1.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        await token0.approve(simpleLiquidity.address, amount0);
        await token1.approve(simpleLiquidity.address, amount1);

        // adding liquidity
        result = await simpleLiquidity.newPosition({
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: 170040,
            tickUpper: 200040,
            slippage: 10
          });

        const tokenId = await positionManager.tokenOfOwnerByIndex(signerAddress, tokenIndex);
        tokenIndex++;

        result = await positionManager.positions(tokenId.toNumber());
        console.log("liquidity =", result[7].toNumber());

        // increase liquidity
        await token0.approve(simpleLiquidity.address, amount0);
        await token1.approve(simpleLiquidity.address, amount1);

        result = await simpleLiquidity.increaseLiquidity({
            tokenId: tokenId.toNumber(),
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: 170040,
            tickUpper: 200040,
            slippage: 10
          });

        result = await positionManager.positions(tokenId.toNumber());
        console.log("updated liquidity =", result[7].toNumber());
        
      });

      it("New liquidity position 0.5 ETH + 1000 USDC ", async function () {
        const token0 = new ethers.Contract(WETH_address, IERC20, signer);
        const token1 = new ethers.Contract(USDC_address, IERC20, signer);

        const amount0 = ethers.utils.parseUnits("0.5", await token0.decimals()).toHexString();
        const amount1 = ethers.utils.parseUnits("1000.0", await token1.decimals()).toHexString();
        const feeTier = 3000;

        // Swap ETH -> token1
        result = await UniV2_router.swapExactETHForTokens(
            100, 
            [WETH_address, token1.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        // approving token1
        await token1.approve(simpleLiquidity.address,  ethers.utils.parseUnits("1000.0", 6).toHexString());

        // adding liquidity
        result = await simpleLiquidity.newPosition({
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: 170040,
            tickUpper: 200040,
            slippage: 10
          }, { value: amount0 });
      });

      it("New liquidity position 10 DAI + 10 USDC ", async function () {
        const DAI_address = '0x6b175474e89094c44da98b954eedeac495271d0f';
        const token0 = new ethers.Contract(DAI_address, IERC20, signer);
        const token1 = new ethers.Contract(USDC_address, IERC20, signer);

        const amount0 = ethers.utils.parseUnits("10.0", await token0.decimals()).toHexString();
        const amount1 = ethers.utils.parseUnits("10.0", await token1.decimals()).toHexString();
        const poolAddress = '0x6c6bc977e13df9b0de53b251522280bb72383700';
        const feeTier = 500;

        const UniV2_router = new ethers.Contract(UniV2_router_address, UniV2_router_ABI, signer);

        // Swap ETH -> token0
        result = await UniV2_router.swapExactETHForTokens(
            100, 
            [WETH_address, token0.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        // Swap ETH -> token1
        result = await UniV2_router.swapExactETHForTokens(
            100, 
            [WETH_address, token1.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        // approving token0
        await token0.approve(simpleLiquidity.address, amount0);

        // approving token1
        await token1.approve(simpleLiquidity.address,  amount1);

        // adding liquidity
        result = await simpleLiquidity.newPosition({
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: -276500,
            tickUpper: -276200,
            slippage: 10
        });
      });

      it("New liquidity position 20 USDC + 0 WBTC ", async function () {
        const WBTC_address = '0x2260fac5e5542a773aa44fbcfedf7c193bc2c599';
        const token0 = new ethers.Contract(USDC_address, IERC20, signer);
        const token1 = new ethers.Contract(WBTC_address, IERC20, signer);

        const amount0 = ethers.utils.parseUnits("20.0", await token0.decimals()).toHexString();
        const amount1 = ethers.utils.parseUnits("0", await token1.decimals()).toHexString();
        const feeTier = 3000;

        const UniV2_router = new ethers.Contract(UniV2_router_address, UniV2_router_ABI, signer);

        // Swap ETH -> token0
        result = await UniV2_router.swapExactETHForTokens(
            0, 
            [WETH_address, token0.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        // approving token0
        await token0.approve(simpleLiquidity.address, amount0);

        // adding liquidity
        result = await simpleLiquidity.newPosition({
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: 63000,
            tickUpper: 64020,
            slippage: 10
        });
      });

      it("New liquidity position 20 USDC + 0 USDT ", async function () {
        const USDT_address = '0xdac17f958d2ee523a2206206994597c13d831ec7';
        const token0 = new ethers.Contract(USDC_address, IERC20, signer);
        const token1 = new ethers.Contract(USDT_address, IERC20, signer);

        const amount0 = ethers.utils.parseUnits("20.0", await token0.decimals()).toHexString();
        const amount1 = ethers.utils.parseUnits("0.0", await token1.decimals()).toHexString();
        const poolAddress = '0x3416cf6c708da44db2624d63ea0aaef7113527c6';
        const feeTier = 100;

        const UniV2_router = new ethers.Contract(UniV2_router_address, UniV2_router_ABI, signer);

        // Swap ETH -> token1
        result = await UniV2_router.swapExactETHForTokens(
            0, 
            [WETH_address, token1.address],
            signerAddress,
            Math.floor(Date.now() / 1000) + 60,
            { value: ethers.utils.parseEther("1.0").toHexString() }
        );

        // approving token0
        await token0.approve(simpleLiquidity.address,  amount0);

        // adding liquidity
        result = await simpleLiquidity.newPosition({
            token0: token0.address,
            token1: token1.address,
            amount0: amount0,
            amount1: amount1,
            feeTier: feeTier,
            tickLower: -10,
            tickUpper: 10,
            slippage: 10
        });


      });

    });
})

