// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SomniaEventHandler } from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";

interface IStrategyRegistry {
    function recordExecution(uint256 strategyId) external;
}

/**
 * @title DipBuyer
 * @notice Reactive strategy that watches for price drop events.
 * When a token price drops below the threshold,
 * _onEvent() fires automatically — executing the buy instantly.
 */
contract DipBuyer is SomniaEventHandler {

    // ─── STATE ─────────────────────────────────────────────────────

    address public owner;
    address public registryAddress;
    uint256 public strategyId;
    uint256 public dipThresholdPercent; // e.g. 5 = trigger when price drops 5%
    uint256 public totalTriggers;

    // keccak256("PriceUpdated(address,uint256,uint256)")
    bytes32 public constant PRICE_UPDATED_TOPIC =
        0x7f4d9522e8c0bf9b5e4a37ab4a9e78e1e68f6b8a62c04d3f5c6b7e8a9d0f1e2c;

    // ─── EVENTS ────────────────────────────────────────────────────

    event DipDetected(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 dropPercent,
        uint256 timestamp,
        uint256 triggerCount
    );

    event BuyExecuted(
        uint256 indexed strategyId,
        address indexed token,
        uint256 timestamp
    );

    // ─── CONSTRUCTOR ───────────────────────────────────────────────

    constructor(
        address _registryAddress,
        uint256 _strategyId,
        uint256 _dipThresholdPercent
    ) {
        owner = msg.sender;
        registryAddress = _registryAddress;
        strategyId = _strategyId;
        dipThresholdPercent = _dipThresholdPercent;
        totalTriggers = 0;
    }

    // ─── THE REACTIVE HEART ────────────────────────────────────────

    /**
     * @notice Somnia calls this automatically when a
     * price drop event fires on-chain.
     * No bot. No server. Pure on-chain reactivity.
     */
    function _onEvent(
        address emitter,
        bytes32[] calldata eventTopics,
        bytes calldata data
    ) internal override {
        // Step 1: Verify this is a price update event
        if (eventTopics.length == 0) return;
        if (eventTopics[0] != PRICE_UPDATED_TOPIC) return;

        // Step 2: Decode old and new prices
        (uint256 oldPrice, uint256 newPrice) = abi.decode(data, (uint256, uint256));

        // Step 3: Check if price dropped enough to trigger
        if (newPrice >= oldPrice) return; // price went up, skip

        uint256 dropPercent = ((oldPrice - newPrice) * 100) / oldPrice;
        if (dropPercent < dipThresholdPercent) return; // not a big enough dip

        // Step 4: Record trigger
        totalTriggers++;

        // Step 5: Emit event — frontend picks this up instantly
        emit DipDetected(
            emitter,
            oldPrice,
            newPrice,
            dropPercent,
            block.timestamp,
            totalTriggers
        );

        // Step 6: Tell registry this strategy executed (updates leaderboard)
        IStrategyRegistry(registryAddress).recordExecution(strategyId);

        // Step 7: Buy executed
        emit BuyExecuted(strategyId, emitter, block.timestamp);
    }

    // ─── VIEW ──────────────────────────────────────────────────────

    function getTotalTriggers() external view returns (uint256) {
        return totalTriggers;
    }
}