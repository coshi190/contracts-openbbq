// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IUniswapV2Router {
    function WETH() external pure returns (address);
    function swapExactTokensForTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external;
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract CMswapUniSmartRoute is Ownable {
    address public feeReceiver;
    uint256 public feeBasis;
    IUniswapV2Router public router;
    IUniswapV2Factory public factory;

    mapping(address => bool) public whitelist;
    address[] public intermediateTokens;

    event FeeTaken(address indexed from, uint256 amount, address token);

    constructor(address _router, address _feeReceiver,address _factory) Ownable(msg.sender) {
        require(_router != address(0), "Invalid router");
        require(_feeReceiver != address(0), "Invalid fee receiver");
        require(_factory != address(0), "Invalid factory");
        factory = IUniswapV2Factory(_factory);

        router = IUniswapV2Router(_router);
        feeReceiver = _feeReceiver;
        feeBasis = 10;
    }

    function setFeeReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid address");
        feeReceiver = _newReceiver;
    }

    function setFeeBasis(uint256 _newBasis) external onlyOwner {
        require(_newBasis <= 1000, "Fee too high");
        feeBasis = _newBasis;
    }

    function addTokensToWhitelist(address[] calldata tokens) external onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (!whitelist[token]) {
                whitelist[token] = true;
                intermediateTokens.push(token);
            }
        }
    }


    function removeTokenFromWhitelist(address token) external onlyOwner {
        whitelist[token] = false;
    }

    function getWhitelistedTokens() external view returns (address[] memory) {
        return intermediateTokens;
    }

    function _takeFee(address token, uint amount) internal returns (uint afterFee) {
        uint feeAmount = (amount * feeBasis) / 10000;
        if (feeAmount > 0) {
            IERC20(token).transfer(feeReceiver, feeAmount);
            emit FeeTaken(msg.sender, feeAmount, token);
        }
        return amount - feeAmount;
    }

function findBestPathAndAmountOut(
    address tokenIn,
    address tokenOut,
    uint amountIn
) external view returns (uint bestAmountOut, address[] memory bestPath) {
    uint amountAfterFee = (amountIn * (10000 - feeBasis)) / 10000;
    bestAmountOut = 0;

    for (uint i = 0; i <= intermediateTokens.length; i++) {
        address[] memory path;

        if (i == intermediateTokens.length) {
            path = new address[](2) ;
            path[0] = tokenIn;
            path[1] = tokenOut;
        } else {
            address mid = intermediateTokens[i];
            if (!whitelist[mid]) continue;
            path = new address[](3) ;
            path[0] = tokenIn;
            path[1] = mid;
            path[2] = tokenOut;
        }

        try router.getAmountsOut(amountAfterFee, path) returns (uint[] memory amounts) {
            uint amountOut = amounts[amounts.length - 1];
            if (amountOut > bestAmountOut) {
                bestAmountOut = amountOut;
                bestPath = path;
            }
        } catch {}
    }
}


    // --- SWAP FUNCTIONS ---

    function swapExactTokensForTokensWithFee(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint afterFee = _takeFee(path[0], amountIn);
        IERC20(path[0]).approve(address(router), afterFee);
        return router.swapExactTokensForTokens(afterFee, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForETHWithFee(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path[path.length - 1] == router.WETH(), "Last path must be WETH");
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint afterFee = _takeFee(path[0], amountIn);
        IERC20(path[0]).approve(address(router), afterFee);
        return router.swapExactTokensForETH(afterFee, amountOutMin, path, to, deadline);
    }

    function swapExactETHForTokensWithFee(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        require(path[0] == router.WETH(), "First path must be WETH");

        uint feeAmount = (msg.value * feeBasis) / 10000;
        uint afterFee = msg.value - feeAmount;

        if (feeAmount > 0) {
            (bool success, ) = feeReceiver.call{value: feeAmount}("");
            require(success, "Fee transfer failed");
            emit FeeTaken(msg.sender, feeAmount, address(0));
        }

        return router.swapExactETHForTokens{value: afterFee}(amountOutMin, path, to, deadline);
    }

    // Supporting Fee-On-Transfer
    function swapExactTokensForTokensSupportingFeeOnTransferTokensWithFee(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint afterFee = _takeFee(path[0], amountIn);
        IERC20(path[0]).approve(address(router), afterFee);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(afterFee, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokensWithFee(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external {
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint afterFee = _takeFee(path[0], amountIn);
        IERC20(path[0]).approve(address(router), afterFee);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(afterFee, amountOutMin, path, to, deadline);
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokensWithFee(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable {
        require(path[0] == router.WETH(), "First path must be WETH");

        uint feeAmount = (msg.value * feeBasis) / 10000;
        uint afterFee = msg.value - feeAmount;

        if (feeAmount > 0) {
            (bool success, ) = feeReceiver.call{value: feeAmount}("");
            require(success, "Fee transfer failed");
            emit FeeTaken(msg.sender, feeAmount, address(0));
        }

        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: afterFee}(amountOutMin, path, to, deadline);
    }
    
    function calculateAmountOutByPath(
        address[] calldata path,
        uint amountIn
    ) external view returns (uint amountOut) {
        uint amountAfterFee = (amountIn * (10000 - feeBasis)) / 10000;
        try router.getAmountsOut(amountAfterFee, path) returns (uint[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    function getPairAddress(address tokenA, address tokenB) external view returns (address) {
    return factory.getPair(tokenA, tokenB);
}


    receive() external payable {}
}
