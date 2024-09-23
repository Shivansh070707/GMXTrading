// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
interface IGMXPositionRouter {
    function increasePositionRequestKeysStart() external view returns (uint256);
    function decreasePositionRequestKeysStart() external view returns (uint256);
    function executeIncreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;
    function executeIncreasePosition(
        bytes32 _requestkey,
        address payable _executionFeeReceiver
    ) external;
    function executeDecreasePositions(
        uint256 _count,
        address payable _executionFeeReceiver
    ) external;
    function getRequestKey(
        address _account,
        uint256 _index
    ) external pure returns (bytes32);

    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) external payable returns (bytes32);

    function createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) external payable returns (bytes32);

    function cancelIncreasePosition(
        bytes32 _key,
        address _executionFeeReceiver
    ) external returns (bool);

    function cancelDecreasePosition(
        bytes32 _key,
        address _executionFeeReceiver
    ) external returns (bool);

    function increasePositionsIndex(
        address _user
    ) external view returns (uint256);
    function decreasePositionsIndex(
        address _user
    ) external view returns (uint256);

    function setPositionKeeper(address keeper, bool isKeeper) external;
    function minExecutionFee() external view returns (uint256);
    function setPricesWithBitsAndExecute(
        uint256 _priceBits,
        uint256 _timestamp,
        uint256 _endIndexForIncreasePositions,
        uint256 _endIndexForDecreasePositions,
        uint256 _maxIncreasePositions,
        uint256 _maxDecreasePositions
    ) external;
    function increasePositionIndexKeys(
        uint256 index
    ) external view returns (bytes32);
}
