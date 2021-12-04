// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;
pragma abicoder v2;

import './libraries/LiquidityAmounts.sol';
import './libraries/TickMath.sol';
import './libraries/FixedPoint96.sol';
import './libraries/PoolAddress.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import "hardhat/console.sol";

contract SimpleLiquidity {
    
    address public immutable factory;
    address public immutable WETH9;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    mapping(address => bool) private approvedSwapTokens;
    mapping(address => bool) private approvedPositionTokens;

    constructor(
        address _factory, 
        address _WETH9,
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISwapRouter _swapRouter
    ) {
        factory = _factory;
        WETH9 = _WETH9;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
    }

    struct NewPositionParams {
        address token0;
        address token1;
        uint amount0;
        uint amount1;
        uint24 feeTier;
        int24 tickLower;
        int24 tickUpper;
        uint8 slippage;
    }

	struct IncreaseLiquidityParams {
		uint tokenId;
		address token0;
		address token1;
        uint amount0;
        uint amount1;
        uint24 feeTier;
        int24 tickLower;
        int24 tickUpper;
        uint8 slippage;
	}

    /**
     * Requirements:
     * slippage 1 - 100 (0.1% - 10%)
     * ticks must be divisible by tickSpacing
    */ 
    function newPosition(NewPositionParams memory p) 
        external 
        payable 
    {
        // Wrap if necessary
        if (msg.value > 0) {
            require(p.token0 == WETH9 || p.token1 == WETH9, 'WETH expected');
            WETH9.call{value: msg.value}(abi.encodeWithSignature("deposit()"));
            require(IERC20Metadata(WETH9).balanceOf(address(this)) == msg.value,'ETH wrap error');
            if (p.token0 == WETH9) {
                p.amount0 = msg.value;
            } else {
                p.amount1 = msg.value;
            }
        }

        // Transfer from sender
        if ( p.amount0 > 0 && !(p.token0 == WETH9 && p.amount0 == msg.value) ) {
            require(IERC20Metadata(p.token0).transferFrom(msg.sender, address(this), p.amount0) == true);
        }
        if (p.amount1 > 0 && !(p.token1 == WETH9 && p.amount1 == msg.value) ) {
            require(IERC20Metadata(p.token1).transferFrom(msg.sender, address(this), p.amount1) == true);
        }
        
        if (p.token0 > p.token1) {
            (p.token0, p.token1) = (p.token1, p.token0);
            (p.amount0, p.amount1) = (p.amount1, p.amount0);
        }

		(uint amount0required, uint amount1required) = calculateTokensRatio(p);
        
        // Swap if necessary
        if (p.amount0 > amount0required) {
            console.log("swap token0 to token1. Amount:", p.amount0 - amount0required);
            
            uint amountOut = swap(
                p.token0, 
                p.token1, 
                p.amount0 - amount0required, 
                (amount1required - p.amount1) * (1000 - p.slippage) / 1000, 
                p.feeTier
            );
            console.log("amountOut =", amountOut);
            console.log("amountOut expected =", amount1required - p.amount1);

            p.amount1 += amountOut;
            p.amount0 = IERC20Metadata(p.token0).balanceOf(address(this));
        } else if (p.amount1 > amount1required) {
            console.log("swap token1 to token0. Amount:", p.amount1 - amount1required);
            
            uint amountOut = swap(
                p.token1, 
                p.token0, 
                p.amount1 - amount1required, 
                (amount0required - p.amount0) * (1000 - p.slippage) / 1000,
                p.feeTier
            );
            console.log("amountOut =", amountOut);
            console.log("amountOut expected =", amount0required - p.amount0);

            p.amount0 += amountOut;
            p.amount1 = IERC20Metadata(p.token1).balanceOf(address(this));
        }

        p.amount0 = IERC20Metadata(p.token0).balanceOf(address(this));
        p.amount1 = IERC20Metadata(p.token1).balanceOf(address(this));
        console.log("balance of token0:", p.amount0);
        console.log("balance of token1:", p.amount1);
        
        // New position
        if (!approvedPositionTokens[p.token0]) {
            TransferHelper.safeApprove(p.token0, address(nonfungiblePositionManager), type(uint).max);
            approvedPositionTokens[p.token0] = true;
            console.log("approving position token0", p.token0);
        }
        if (!approvedPositionTokens[p.token1]) {
            TransferHelper.safeApprove(p.token1, address(nonfungiblePositionManager), type(uint).max);
            approvedPositionTokens[p.token1] = true;
            console.log("approving position token1", p.token1);
        }

        // Mint
        (, uint128 liquidity, uint amount0, uint amount1) = nonfungiblePositionManager.mint(INonfungiblePositionManager.MintParams({
            token0: p.token0,
            token1: p.token1,
            fee: p.feeTier,
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            amount0Desired: p.amount0,
            amount1Desired: p.amount1,
            amount0Min: p.amount0 * (1000 - p.slippage) / 1000,
            amount1Min: p.amount1 * (1000 - p.slippage) / 1000,
            recipient: msg.sender,
            deadline: block.timestamp
        }));
		console.log("liquidity =", liquidity);
		console.log("amount0 =", amount0);
		console.log("amount1 =", amount1);
        
        // Refunds
        if (p.amount0 - amount0 > 0) {
            console.log("refund token0:", p.amount0 - amount0);
            IERC20Metadata(p.token0).transfer(msg.sender, p.amount0 - amount0);
        }
        if (p.amount1 - amount1 > 0) {
            console.log("refund token1:", p.amount1 - amount1);
            IERC20Metadata(p.token1).transfer(msg.sender, p.amount1 - amount1);
        }
    }

    /**
     * Requirements:
     * slippage 1 - 100 (0.1% - 10%)
    */ 
	function increaseLiquidity(IncreaseLiquidityParams memory p)
        external
        payable
	{
        // Wrap if necessary
        if (msg.value > 0) {
            require(p.token0 == WETH9 || p.token1 == WETH9, 'WETH expected');
            WETH9.call{value: msg.value}(abi.encodeWithSignature("deposit()"));
            require(IERC20Metadata(WETH9).balanceOf(address(this)) == msg.value,'ETH wrap error');
            if (p.token0 == WETH9) {
                p.amount0 = msg.value;
            } else {
                p.amount1 = msg.value;
            }
        }

        // Transfer from sender
        if ( p.amount0 > 0 && !(p.token0 == WETH9 && p.amount0 == msg.value) ) {
            require(IERC20Metadata(p.token0).transferFrom(msg.sender, address(this), p.amount0) == true);
        }
        if (p.amount1 > 0 && !(p.token1 == WETH9 && p.amount1 == msg.value) ) {
            require(IERC20Metadata(p.token1).transferFrom(msg.sender, address(this), p.amount1) == true);
        }
        
        if (p.token0 > p.token1) {
            (p.token0, p.token1) = (p.token1, p.token0);
            (p.amount0, p.amount1) = (p.amount1, p.amount0);
        }
        (uint amount0required, uint amount1required) = calculateTokensRatio(NewPositionParams({
            token0: p.token0,
            token1: p.token1,
            amount0: p.amount0,
            amount1: p.amount1,
            feeTier: p.feeTier,
            tickLower: p.tickLower,
            tickUpper: p.tickUpper,
            slippage: p.slippage
        }));

        // Swap if necessary
        if (p.amount0 > amount0required) {
            console.log("swap token0 to token1. Amount:", p.amount0 - amount0required);
            
            uint amountOut = swap(
                p.token0, 
                p.token1, 
                p.amount0 - amount0required, 
                (amount1required - p.amount1) * (1000 - p.slippage) / 1000, 
                p.feeTier
            );
            console.log("amountOut =", amountOut);
            console.log("amountOut expected =", amount1required - p.amount1);

            p.amount1 += amountOut;
            p.amount0 = IERC20Metadata(p.token0).balanceOf(address(this));
        } else if (p.amount1 > amount1required) {
            console.log("swap token1 to token0. Amount:", p.amount1 - amount1required);
            
            uint amountOut = swap(
                p.token1, 
                p.token0, 
                p.amount1 - amount1required, 
                (amount0required - p.amount0) * (1000 - p.slippage) / 1000,
                p.feeTier
            );
            console.log("amountOut =", amountOut);
            console.log("amountOut expected =", amount0required - p.amount0);

            p.amount0 += amountOut;
            p.amount1 = IERC20Metadata(p.token1).balanceOf(address(this));
        }

        // Increase
		(uint128 liquidity, uint amount0, uint amount1) = nonfungiblePositionManager.increaseLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams({
			tokenId: p.tokenId,
        	amount0Desired: p.amount0,
        	amount1Desired: p.amount1,
        	amount0Min: p.amount0 * (1000 - p.slippage) / 1000,
        	amount1Min: p.amount1 * (1000 - p.slippage) / 1000,
        	deadline: block.timestamp
		}));
		console.log("liquidity =", liquidity);
		console.log("amount0 =", amount0);
		console.log("amount1 =", amount1);

        // Refunds
        if (p.amount0 - amount0 > 0) {
            console.log("refund token0:", p.amount0 - amount0);
            IERC20Metadata(p.token0).transfer(msg.sender, p.amount0 - amount0);
        }
        if (p.amount1 - amount1 > 0) {
            console.log("refund token1:", p.amount1 - amount1);
            IERC20Metadata(p.token1).transfer(msg.sender, p.amount1 - amount1);
        }
	}
        
    /** 
    * @dev Calculates token1/token0 price from sqrtPriceX96
    * 
    * Requirements:
    * 0 < tokenDecimals <= 18
    * 
    */
    function sqrtPriceX96ToPrice(uint160 sqrtPriceX96, uint8 tokenDecimals) 
        internal 
        view 
        virtual 
        returns (uint result) 
    {
        require(tokenDecimals > 0, 'decimals == 0');
        require(tokenDecimals <= 18, 'decimals > 18');
        result = FullMath.mulDiv(uint(sqrtPriceX96), uint(sqrtPriceX96), FixedPoint96.Q96);
        return FullMath.mulDiv(result, 10 ** tokenDecimals, FixedPoint96.Q96);
    }

    /** 
    * @dev Calculates current tokens ratio in pool
    * 
    */
	function calculateTokensRatio(NewPositionParams memory p) 
		internal 
        view
		returns (
			uint amount0required, 
			uint amount1required
		) 
	{
		address poolAddress = PoolAddress.computeAddress(
			factory, 
			PoolAddress.getPoolKey(p.token0, p.token1, p.feeTier)
		);
        uint8 decimals0 = IERC20Metadata(p.token0).decimals();
		(uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        uint price = sqrtPriceX96ToPrice(sqrtPriceX96, decimals0);
        uint160 sqrtPriceMinX96 = TickMath.getSqrtRatioAtTick(p.tickLower);
        uint160 sqrtPriceMaxX96 = TickMath.getSqrtRatioAtTick(p.tickUpper);

        console.log("sqrtPriceMinX96=", sqrtPriceMinX96);
        console.log("sqrtPriceX96=", sqrtPriceX96);
        console.log("sqrtPriceMaxX96=", sqrtPriceMaxX96);
        console.log("price=", price);
        console.log("token0.decimals=", decimals0);

        if (sqrtPriceX96 >= sqrtPriceMaxX96) {
            // all in token1
            amount1required = FullMath.mulDiv(p.amount0, price, 10**decimals0) + p.amount1;
        } else if (sqrtPriceX96 <= sqrtPriceMinX96) {
            // all in token0
            amount0required = p.amount0 + FullMath.mulDiv(p.amount1, 10**decimals0, price);
        } else {
            // we need token0/token1 ratio
            // let amount0 = 1
            
            uint amount0tmp = 1 * 10 ** (decimals0);

            uint128 L = LiquidityAmounts.getLiquidityForAmount0(
				sqrtPriceX96,
				sqrtPriceMaxX96,
				amount0tmp
			);

            uint amount1tmp = LiquidityAmounts.getAmount1ForLiquidity(
                sqrtPriceX96,
                sqrtPriceMinX96,
                L
            );

            require(amount1tmp > 0);

            console.log("L=", L);
            console.log("amount0tmp=", amount0tmp);
            console.log("amount1tmp=", amount1tmp);
            
            uint sum_in_token0 = p.amount0 + FullMath.mulDiv(p.amount1, 10**decimals0, price);
            uint amount1tmp_in_token0 = FullMath.mulDiv(amount1tmp, 10**decimals0, price);

            //uint part = sum_in_token0 / (amount0tmp + amount1tmp_in_token0);
            uint part_Q96 = FullMath.mulDiv(sum_in_token0, FixedPoint96.Q96, amount0tmp + amount1tmp_in_token0);
            console.log("part = ", part_Q96);

            amount0required = FullMath.mulDiv(part_Q96, amount0tmp, FixedPoint96.Q96);

            //amount1required = (part * amount1tmp_in_token0) * price / (10**decimals0);
            amount1required = FullMath.mulDiv(part_Q96, amount1tmp_in_token0, FixedPoint96.Q96);
            amount1required = FullMath.mulDiv(amount1required, price, 10**decimals0);
        }

        console.log("amount0", p.amount0);
        console.log("amount1", p.amount1);
        console.log("amount0required", amount0required);
        console.log("amount1required", amount1required);
	}

    function swap(address tokenIn, address tokenOut, uint amountIn, uint amountOutMin, uint24 feeTier)
        internal
        returns(uint amountOut)
    {
        if (!approvedSwapTokens[tokenIn]) {
            TransferHelper.safeApprove(tokenIn, address(swapRouter), type(uint).max);
            approvedSwapTokens[tokenIn] = true;
            console.log("approving swap token", tokenIn);
        }
        
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: feeTier,   // TODO determine the best feeTier
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        return swapRouter.exactInputSingle(swapParams);
    }
}
