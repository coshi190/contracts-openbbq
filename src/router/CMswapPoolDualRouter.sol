// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ICommudaoJULP {
    function JUSDTAddress() external view returns (address);
    function getReserve() external view returns (uint256);
    function jbcToJusdt(uint256 _minTokens) external payable;
    function jusdtToJbc(uint256 _tokensSold, uint256 _minJbc) external;
}

interface ICommudaoJCLP {
    function cmjTokenAddress() external view returns (address);
    function getReserve() external view returns (uint256);
    function jbcToCmj(uint256 _minTokens) external payable;
    function cmjToJbc(uint256 _tokensSold, uint256 _minJbc) external;
}

contract CMswapPoolDualRouter {
    address public owner;
    address public immutable juPool = 0x280608DD7712a5675041b95d0000B9089903B569;
    address public immutable jcPool = 0x472d0e2E9839c140786D38110b3251d5ED08DF41;
    address public feeReceiver = 0xCA811301C650C92fD45ed32A81C0B757C61595b6;

    mapping(address => uint256) public feePercentOfPool; // per pool: 50 = 0.5%

    bool private locked;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    modifier noReentrancy() {
        require(!locked, "Reentrancy attack!");
        locked = true;
        _;
        locked = false;
    }

    constructor() {
        owner = msg.sender;
        feePercentOfPool[juPool] = 50; // 0.5%
        feePercentOfPool[jcPool] = 30; // 0.3%
    }

    receive() external payable {}

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        feeReceiver = _feeReceiver;
    }

    function setFeePercent(address pool, uint256 _fee) external onlyOwner {
        require(_fee <= 1000, "Too high");
        feePercentOfPool[pool] = _fee;
    }

    function setOwner(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Zero address");
        owner = _newOwner;
    }

    function _swapNativeToToken(address pool, uint256 minOut) internal {
        require(msg.value > 0, "No input");

        uint256 fee = (msg.value * feePercentOfPool[pool]) / 10000;
        uint256 amountAfterFee = msg.value - fee;

        (bool sentFee, ) = payable(feeReceiver).call{value: fee}("");
        require(sentFee, "Fee transfer failed");

        address tokenOut;
        uint256 balanceBefore;

        if (pool == juPool) {
            tokenOut = ICommudaoJULP(pool).JUSDTAddress();
            balanceBefore = IERC20(tokenOut).balanceOf(address(this));
            ICommudaoJULP(pool).jbcToJusdt{value: amountAfterFee}(minOut);
        } else if (pool == jcPool) {
            tokenOut = ICommudaoJCLP(pool).cmjTokenAddress();
            balanceBefore = IERC20(tokenOut).balanceOf(address(this));
            ICommudaoJCLP(pool).jbcToCmj{value: amountAfterFee}(minOut);
        }

        uint256 received = IERC20(tokenOut).balanceOf(address(this)) - balanceBefore;
        require(received >= minOut, "Slippage exceeded");
        require(IERC20(tokenOut).transfer(msg.sender, received), "Token transfer failed");
    }

    function _swapTokenToNative(address pool, address tokenIn, uint256 amountIn, uint256 minOut) internal {
        require(amountIn > 0, "No input");

        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TransferFrom failed");

        uint256 fee = (amountIn * feePercentOfPool[pool]) / 10000;
        uint256 amountAfterFee = amountIn - fee;

        require(IERC20(tokenIn).transfer(feeReceiver, fee), "Fee transfer failed");
        require(IERC20(tokenIn).approve(pool, amountAfterFee), "Approve failed");

        uint256 balanceBefore = address(this).balance;

        if (pool == juPool) {
            ICommudaoJULP(pool).jusdtToJbc(amountAfterFee, minOut);
        } else if (pool == jcPool) {
            ICommudaoJCLP(pool).cmjToJbc(amountAfterFee, minOut);
        }

        uint256 received = address(this).balance - balanceBefore;
        require(received >= minOut, "Slippage exceeded");

        (bool sent, ) = payable(msg.sender).call{value: received}("");
        require(sent, "Send failed");

    }

    function swapJU(uint256 minOut) external payable noReentrancy {
        _swapNativeToToken(juPool, minOut);
    }

    function swapJC(uint256 minOut) external payable noReentrancy {
        _swapNativeToToken(jcPool, minOut);
    }

    function swapJUSDTtoJBC(uint256 amountIn, uint256 minOut) external noReentrancy {
        address tokenIn = ICommudaoJULP(juPool).JUSDTAddress();
        _swapTokenToNative(juPool, tokenIn, amountIn, minOut);
    }

    function swapCMJtoJBC(uint256 amountIn, uint256 minOut) external noReentrancy {
        address tokenIn = ICommudaoJCLP(jcPool).cmjTokenAddress();
        _swapTokenToNative(jcPool, tokenIn, amountIn, minOut);
    }

    function getExpectedJBCFromToken(address pool, uint256 tokenInAmount) external view returns (uint256) {
        require(tokenInAmount > 0, "Input must be > 0");

        uint256 reserveToken;
        uint256 reserveJBC = address(pool).balance;

        if (pool == juPool) {
            reserveToken = ICommudaoJULP(pool).getReserve();
        } else if (pool == jcPool) {
            reserveToken = ICommudaoJCLP(pool).getReserve();
        } else {
            revert("Invalid pool");
        }

        uint256 feePercent = feePercentOfPool[pool];
        uint256 amountAfterFee = (tokenInAmount * (10000 - feePercent)) / 10000;

        uint256 amountInWithFee = amountAfterFee * 997;
        uint256 numerator = amountInWithFee * reserveJBC;
        uint256 denominator = (reserveToken * 1000) + amountInWithFee;
        return denominator == 0 ? 0 : numerator / denominator;
    }

    function getExpectedTokenFromJBC(address pool, uint256 jbcInAmount) external view returns (uint256) {
        require(jbcInAmount > 0, "Input must be > 0");

        uint256 reserveToken;
        uint256 reserveJBC = address(pool).balance;

        if (pool == juPool) {
            reserveToken = ICommudaoJULP(pool).getReserve();
        } else if (pool == jcPool) {
            reserveToken = ICommudaoJCLP(pool).getReserve();
        } else {
            revert("Invalid pool");
        }

        uint256 feePercent = feePercentOfPool[pool];
        uint256 amountAfterFee = (jbcInAmount * (10000 - feePercent)) / 10000;

        uint256 amountInWithFee = amountAfterFee * 997;
        uint256 numerator = amountInWithFee * reserveToken;
        uint256 denominator = (reserveJBC * 1000) + amountInWithFee;
        return denominator == 0 ? 0 : numerator / denominator;
    }


    function getAllReserves() external view returns (
        uint256 juReserveNative,
        uint256 juReserveToken,
        uint256 jcReserveNative,
        uint256 jcReserveToken
    ) {
        juReserveToken = ICommudaoJULP(juPool).getReserve();
        juReserveNative = address(juPool).balance;
        jcReserveToken = ICommudaoJCLP(jcPool).getReserve();
        jcReserveNative = address(jcPool).balance;
    }

    function getTokenAddresses() external view returns (address jusdt, address cmj) {
        jusdt = ICommudaoJULP(juPool).JUSDTAddress();
        cmj = ICommudaoJCLP(jcPool).cmjTokenAddress();
    }
}