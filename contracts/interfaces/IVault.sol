// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IVault {
    function deposit(address user, uint256 amount) external;
    function withdraw(address user, uint256 amount) external;
    function transferToUserAccount(
        address user,
        address userAccount,
        uint256 amount
    ) external;
    function getBalance(address user) external view returns (uint256);
    function getMaxPrice(address token) external view returns (uint256);
    function depositForUser(address user, uint256 amount) external;
}
