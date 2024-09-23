// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IGMXPositionRouter.sol";
import "./interfaces/IGMXReader.sol";
import "./interfaces/IGMX.sol";
import "./interfaces/IGMXRouter.sol";
import "./interfaces/IVault.sol";
import "./UserAccount.sol";

contract GMXTrading is Ownable, IGMX {
    uint256 public constant PERFORMANCE_FEE_BPS = 100; // 1% performance fee
    address public immutable userAccountImplementation;
    IGMXPositionRouter public immutable positionRouter;
    IGMXRouter public immutable gmxRouter;
    IGMXReader public immutable gmxReader;
    IVault public immutable vault;
    address public immutable gmxVault;
    uint256 public constant SLIPPAGE_BPS = 500; // 5% slippage tolerance
    address public usdcToken;

    mapping(address => address) public userAccounts;
    mapping(address => bool) public whitelistedUsers;
    address[] public supportedAssets;

    event AccountCreated(address indexed user, address accountAddress);
    event UserWhitelisted(address indexed user);
    event UserRemovedFromWhitelist(address indexed user);
    event AssetAdded(address indexed asset);
    event AssetRemoved(address indexed asset);

    error AccountAlreadyExists();
    error UserNotWhitelisted();
    error AccountDoesNotExist();
    error AssetAlreadySupported();
    error AssetNotFound();
    error NoFeesToClaim();

    constructor(
        address _positionRouter,
        address _gmxRouter,
        address _gmxReader,
        address _gmxVault,
        address _usdcToken,
        address _vault,
        address[] memory _initialSupportedAssets
    ) Ownable(msg.sender) {
        positionRouter = IGMXPositionRouter(_positionRouter);
        gmxRouter = IGMXRouter(_gmxRouter);
        gmxReader = IGMXReader(_gmxReader);
        gmxVault = _gmxVault;
        vault = IVault(_vault);
        usdcToken = _usdcToken;
        userAccountImplementation = address(new UserAccount());
        supportedAssets = _initialSupportedAssets;
    }

    function createAccount() external override returns (address) {
        require(userAccounts[msg.sender] == address(0), AccountAlreadyExists());
        require(whitelistedUsers[msg.sender], UserNotWhitelisted());

        address clone = Clones.clone(userAccountImplementation);
        UserAccount(clone).initialize(
            msg.sender,
            address(this),
            address(positionRouter),
            address(gmxRouter),
            address(vault),
            usdcToken,
            supportedAssets
        );

        userAccounts[msg.sender] = clone;
        emit AccountCreated(msg.sender, clone);
        return clone;
    }

    function transferMargin(uint256 amount) external override {
        require(whitelistedUsers[msg.sender], UserNotWhitelisted());
        address userAccount = userAccounts[msg.sender];
        require(userAccount != address(0), AccountDoesNotExist());

        vault.deposit(msg.sender, amount);
    }

    function openPosition(
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable override returns (bytes32) {
        require(whitelistedUsers[msg.sender], UserNotWhitelisted());
        address userAccount = userAccounts[msg.sender];
        require(userAccount != address(0), AccountDoesNotExist());
        uint256 minOut = (amountIn * (10000 - SLIPPAGE_BPS)) / 10000;

        return
            UserAccount(userAccount).openPosition{value: executionFee}(
                indexToken,
                amountIn,
                sizeDelta,
                minOut,
                isLong,
                acceptablePrice,
                executionFee
            );
    }

    function closePosition(
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable override {
        require(whitelistedUsers[msg.sender], UserNotWhitelisted());
        address userAccount = userAccounts[msg.sender];
        require(userAccount != address(0), AccountDoesNotExist());
        uint256 minOut = (amountIn * (10000 - SLIPPAGE_BPS)) / 10000;

        UserAccount(userAccount).closePosition{value: executionFee}(
            indexToken,
            amountIn,
            sizeDelta,
            minOut,
            isLong,
            acceptablePrice,
            executionFee
        );
    }

    function cancelOrder(bytes32 orderId) external override {
        require(whitelistedUsers[msg.sender], UserNotWhitelisted());
        address userAccount = userAccounts[msg.sender];
        require(userAccount != address(0), AccountDoesNotExist());
        UserAccount(userAccount).cancelOrder(orderId);
    }

    function getPositions(
        address user,
        address[] memory _collateralTokens,
        address[] memory _indexTokens,
        bool[] memory _isLong
    ) external view returns (uint256[] memory) {
        address userAccount = userAccounts[user];
        require(userAccount != address(0), AccountDoesNotExist());

        return
            gmxReader.getPositions(
                gmxVault,
                userAccount,
                _collateralTokens,
                _indexTokens,
                _isLong
            );
    }

    function addToWhitelist(address user) external onlyOwner {
        whitelistedUsers[user] = true;
        emit UserWhitelisted(user);
    }

    function removeFromWhitelist(address user) external onlyOwner {
        whitelistedUsers[user] = false;
        emit UserRemovedFromWhitelist(user);
    }

    function addSupportedAsset(address asset) external onlyOwner {
        require(!isAssetSupported(asset), AssetAlreadySupported());
        supportedAssets.push(asset);
        emit AssetAdded(asset);
    }

    function removeSupportedAsset(address asset) external onlyOwner {
        for (uint i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                supportedAssets[i] = supportedAssets[
                    supportedAssets.length - 1
                ];
                supportedAssets.pop();
                emit AssetRemoved(asset);
                return;
            }
        }
        revert AssetNotFound();
    }

    function isAssetSupported(address asset) public view returns (bool) {
        for (uint i = 0; i < supportedAssets.length; i++) {
            if (supportedAssets[i] == asset) {
                return true;
            }
        }
        return false;
    }

    function getSupportedAssets() external view returns (address[] memory) {
        return supportedAssets;
    }

    function getUserAccount(address user) external view returns (address) {
        return userAccounts[user];
    }

    function getUserBalance(address user) external view returns (uint256) {
        return vault.getBalance(user);
    }

    function claimPerformanceFees() external onlyOwner {
        uint256 feeAmount = IERC20(usdcToken).balanceOf(address(this));
        require(feeAmount > 0, NoFeesToClaim());
        IERC20(usdcToken).transfer(owner(), feeAmount);
    }

    receive() external payable {}
}
