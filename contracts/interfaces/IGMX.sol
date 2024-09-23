// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
interface IGMX {
    function createAccount() external returns (address);
    function transferMargin(uint256 amount) external;
    function openPosition(
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable returns (bytes32);
    function closePosition(
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable;
    function cancelOrder(bytes32 orderId) external;
}
