// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Vault {
    IERC20 public immutable usdcToken;
    mapping(address => uint256) public balances;

    error InsufficientBalance();
    error TransferFailed();

    constructor(address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
    }

    function deposit(address user, uint256 amount) external {
        require(
            usdcToken.transferFrom(user, address(this), amount),
            TransferFailed()
        );
        balances[user] += amount;
    }
    function depositForUser(address user, uint256 amount) external {
        require(
            usdcToken.transferFrom(msg.sender, address(this), amount),
            TransferFailed()
        );

        balances[user] += amount;
    }

    function withdraw(address user, uint256 amount) external {
        require(balances[user] >= amount, InsufficientBalance());
        balances[user] -= amount;
        require(usdcToken.transfer(user, amount), TransferFailed());
    }

    function transferToUserAccount(
        address user,
        address userAccount,
        uint256 amount
    ) external {
        require(balances[user] >= amount, InsufficientBalance());
        balances[user] -= amount;
        require(usdcToken.transfer(userAccount, amount), TransferFailed());
    }

    function getBalance(address user) external view returns (uint256) {
        return balances[user];
    }
}
