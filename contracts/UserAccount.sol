// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGMXPositionRouter.sol";
import "./interfaces/IGMXReader.sol";
import "./interfaces/IGMX.sol";
import "./interfaces/IGMXRouter.sol";
import "./interfaces/IVault.sol";

contract UserAccount {
    IGMXPositionRouter public positionRouter;
    IGMXRouter public gmxRouter;
    IVault public vault;
    IERC20 public usdcToken;
    address public factory;
    address public owner;

    mapping(address => bool) public supportedAssets;
    mapping(bytes32 => uint256) public positionAmountIn;

    uint256 public constant PERFORMANCE_FEE_BPS = 100; // 1% performance fee

    error AlreadyInitialized();
    error OnlyFactoryCanCall();
    error UnsupportedAsset();
    error InsufficientBalance();
    error Unauthorized();
    error FailedToCancelOrder();

    function initialize(
        address _owner,
        address _factory,
        address _positionRouter,
        address _gmxRouter,
        address _vault,
        address _usdcToken,
        address[] memory _supportedAssets
    ) external {
        require(factory == address(0), AlreadyInitialized());
        owner = _owner;
        factory = _factory;
        positionRouter = IGMXPositionRouter(_positionRouter);
        gmxRouter = IGMXRouter(_gmxRouter);
        vault = IVault(_vault);
        usdcToken = IERC20(_usdcToken);

        usdcToken.approve(address(positionRouter), type(uint256).max);
        gmxRouter.approvePlugin(address(positionRouter));

        for (uint i = 0; i < _supportedAssets.length; i++) {
            supportedAssets[_supportedAssets[i]] = true;
        }
    }

    modifier onlyFactory() {
        require(msg.sender == factory, OnlyFactoryCanCall());
        _;
    }

    function openPosition(
        address indexToken,
        uint256 amountIn,
        uint256 sizeDelta,
        uint256 minOut,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable onlyFactory returns (bytes32) {
        require(supportedAssets[indexToken], UnsupportedAsset());
        require(vault.getBalance(owner) >= amountIn, InsufficientBalance());

        vault.transferToUserAccount(owner, address(this), amountIn);
        usdcToken.approve(address(gmxRouter), amountIn);

        address[] memory path;
        if (isLong) {
            path = new address[](2);
            path[0] = address(usdcToken);
            path[1] = indexToken;
        } else {
            path = new address[](1);
            path[0] = address(usdcToken);
        }

        bytes32 positionKey = positionRouter.createIncreasePosition{
            value: executionFee
        }(
            path,
            indexToken,
            amountIn,
            minOut,
            sizeDelta,
            isLong,
            acceptablePrice,
            executionFee,
            bytes32(0), // referralCode
            address(this) // callbackTarget
        );

        positionAmountIn[positionKey] = amountIn;
        return positionKey;
    }

    function closePosition(
        address indexToken,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 minOut,
        bool isLong,
        uint256 acceptablePrice,
        uint256 executionFee
    ) external payable onlyFactory {
        address[] memory path;
        if (isLong) {
            path = new address[](1);
            path[0] = address(indexToken);
        } else {
            path = new address[](2);
            path[0] = address(usdcToken);
            path[1] = indexToken;
        }

        positionRouter.createDecreasePosition{value: executionFee}(
            path,
            indexToken,
            collateralDelta,
            sizeDelta,
            isLong,
            address(this),
            acceptablePrice,
            minOut,
            executionFee,
            false, // withdrawETH
            address(this) // callbackTarget
        );
    }

    function cancelOrder(bytes32 orderId) external onlyFactory {
        bool cancelled = positionRouter.cancelIncreasePosition(orderId, owner);
        if (!cancelled) {
            cancelled = positionRouter.cancelDecreasePosition(orderId, owner);
        }
        require(cancelled, FailedToCancelOrder());
    }

    function gmxPositionCallback(
        bytes32 positionKey,
        bool isExecuted,
        bool isIncrease
    ) external {
        require(msg.sender == address(positionRouter), Unauthorized());
        if (isExecuted && !isIncrease) {
            uint256 amountIn = positionAmountIn[positionKey];
            uint256 currentBalance = usdcToken.balanceOf(address(this));

            if (currentBalance > amountIn) {
                uint256 profit = currentBalance - amountIn;
                uint256 performanceFee = (profit * PERFORMANCE_FEE_BPS) / 10000;
                usdcToken.transfer(factory, performanceFee);
                usdcToken.approve(address(vault), amountIn);
                vault.depositForUser(owner, amountIn);
                usdcToken.transfer(owner, profit - performanceFee);
            } else {
                usdcToken.approve(address(vault), currentBalance);
                vault.depositForUser(owner, currentBalance);
            }

            positionAmountIn[positionKey] -= currentBalance;
        } else if (!isExecuted) {
            uint256 currentBalance = usdcToken.balanceOf(address(this));
            usdcToken.approve(address(vault), currentBalance);
            vault.depositForUser(owner, currentBalance);
            positionAmountIn[positionKey] -= currentBalance;
        }
    }
}
