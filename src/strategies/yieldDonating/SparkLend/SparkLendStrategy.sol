// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from    "../../../interfaces/SparkLend/IPool.sol";
import {IAToken} from "../../../interfaces/SparkLend/IAToken.sol";

/**
 * @title YieldDonating Strategy Template
 * @author Octant
 * @notice Template for creating YieldDonating strategies that mint profits to donationAddress
 * @dev This strategy template works with the TokenizedStrategy pattern where
 *      initialization and management functions are handled by a separate contract.
 *      The strategy focuses on the core yield generation logic.
 *
 *      NOTE: To implement permissioned functions you can use the onlyManagement,
 *      onlyEmergencyAuthorized and onlyKeepers modifiers
 */
contract SparkLendStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    /// @notice Address of the yield source (e.g., Aave pool, Compound, Yearn vault)
    IPool public immutable pool;
    IAToken public immutable aToken;
    uint256 internal decimals;

    /**
     * @param _asset Address of the underlying asset
     * @param _name Strategy name
     * @param _management Address with management role
     * @param _keeper Address with keeper role
     * @param _emergencyAdmin Address with emergency admin role
     * @param _donationAddress Address that receives donated/minted yield
     * @param _enableBurning Whether loss-protection burning from donation address is enabled
     * @param _tokenizedStrategyAddress Address of TokenizedStrategy implementation
     */
    constructor(
        address _yieldSource,
        address _asset,
        string memory _name,
        address _management,
        address _keeper,
        address _emergencyAdmin,
        address _donationAddress,
        bool _enableBurning,
        address _tokenizedStrategyAddress
    )
        BaseStrategy(
            _asset,
            _name,
            _management,
            _keeper,
            _emergencyAdmin,
            _donationAddress,
            _enableBurning,
            _tokenizedStrategyAddress
        )
    {
        pool = IPool(_yieldSource);
        aToken = IAToken(pool.getReserveData(_asset).aTokenAddress);

        require(address(aToken) != address(0), "aToken not found for asset");


        decimals = ERC20(address(aToken)).decimals();
        // max allow Yield source to withdraw assets
        ERC20(_asset).forceApprove(_yieldSource, type(uint256).max);

    }

    /**
     * @dev Deploys funds into the yield source
     * @param _amount Amount of assets to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        pool.supply(address(asset), _amount, address(this), 0);
    }

    /**
     * @dev Withdraws funds from the yield source
     * @param _amount Amount of assets to withdraw
     */
    function _freeFunds(uint256 _amount) internal override {
        pool.withdraw(address(asset), _amount, address(this));
 }

    /**
     * @dev Harvests yield from the yield source and reports total assets
     * @return _totalAssets Total assets managed by the strategy after harvesting
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {

        _totalAssets = totalAssetsBalance() + totalSharesBalance();
    }

    /**
     * @notice Gets the total assets managed by the strategy
     * @return . The total amount of `asset` managed by the strategy.
     */
    function totalAssetsBalance() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }


    function totalSharesBalance() public view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

 
    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @return . The available amount that can be withdrawn.
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return totalAssetsBalance() + totalSharesBalance();
    }

    /**
     * @notice Gets the max amount of `asset` that can be deposited.
     * @dev Can be overridden to implement deposit limits.
     * @param . The address that will deposit.
     * @return . The available amount that can be deposited.
     */
    function availableDepositLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return type(uint256).max;
    }

    /**
     * @dev Emergency withdrawal of assets after strategy shutdown
     * @param _amount Amount of assets to withdraw in asset base units
     */
    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        _freeFunds(_amount);
    }
}
