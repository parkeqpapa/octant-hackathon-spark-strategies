// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseStrategy} from "@octant-core/core/BaseStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISparkVault} from "../../../interfaces/SparkSavings/SparkVault.sol";


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
contract SparkSavingsStrategy is BaseStrategy {
    using SafeERC20 for ERC20;

    /// @notice Address of the yield source (e.g., Aave pool, Compound, Yearn vault)
    ISparkVault public immutable sparkVault;

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
        sparkVault = ISparkVault(_yieldSource);

        // max allow Yield source to withdraw assets
        require(sparkVault.asset() == _asset, "Asset mismatch with yield source");
        ERC20(_asset).forceApprove(_yieldSource, type(uint256).max);
     
    }

  
    /**
     * @dev Deploys funds into the yield source
     * @param _amount Amount of assets to deploy
     */
    function _deployFunds(uint256 _amount) internal override {
        sparkVault.deposit(_amount, address(this));
    }

    /**
     * @dev Withdraws funds from the yield source
     * @param _amount Amount of assets to withdraw
     */
    function _freeFunds(uint256 _amount) internal override {
        sparkVault.withdraw(_amount, address(this), address(this));

    }

    /**
     * @dev Performs accounting of all yield and returns the total
     * @return _totalAssets The total amount of 'asset' managed by the strategy.
     */
    function _harvestAndReport() internal view override returns (uint256 _totalAssets) {
        uint256 shares = sparkVault.balanceOf(address(this));
        uint256 assetsClaim = sparkVault.convertToAssets(shares);
        uint256 assetsIdle = asset.balanceOf(address(this));
        _totalAssets = assetsClaim + assetsIdle;
    }

    /**
     * @notice Gets the total shares managed by the strategy
     * @return . The total amount of shares managed by the strategy.
     */
    function totalSharesBalance() public view returns (uint256) {
        return sparkVault.balanceOf(address(this));
    }

    /**
     * @notice Gets the total assets managed by the strategy
     * @return . The total amount of `asset` managed by the strategy.
     */
    function totalAssetsBalance() public view returns (uint256) {
      return asset.balanceOf(address(this));
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Can be overridden to implement withdrawal limits.
     * @return . The available amount that can be withdrawn.
     */
    function availableWithdrawLimit(address /*_owner*/) public view virtual override returns (uint256) {
        return asset.balanceOf(address(this)) + sparkVault.maxWithdraw(address(this));
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
        if (_amount == type(uint256).max) {
            uint256 assetsToWithdraw = sparkVault.convertToAssets(sparkVault.balanceOf(address(this)));
            _freeFunds(assetsToWithdraw);
        } else {
            _freeFunds(_amount);
        }
    }
}
