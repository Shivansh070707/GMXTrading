// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
interface IGMXReader {
    function getPositions(
        address _vault,
        address _account,
        address[] calldata _collateralTokens,
        address[] calldata _indexTokens,
        bool[] calldata _isLong
    ) external view returns (uint256[] memory);
}
