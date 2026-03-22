// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SomniaEventHandler } from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";

interface IStrategyRegistry {
    function recordExecution(uint256 strategyId) external;
}

/**
 * @title LiquidationShield
 * @notice Reactive strategy that watches for liquidation events.
 * When a liquidation is detected on-chain, _onEvent() fires
 * automatically — protecting subscribed users instantly.
 */
contract LiquidationShield is SomniaEventHandler {

    // ─── STATE ─────────────────────────────────────────────────────

    address public owner;
    address public registryAddress;
    uint256 public strategyId;
    uint256 public totalTriggers;

    // keccak256("Liquidation(address,address,uint256,uint256)")
    // This is a common liquidation event signature used in DeFi protocols
    bytes32 public constant LIQUIDATION_TOPIC =
        0x298637f684da70674f26509b10f07ec2fbc77a335ab1e7d6215a4b2484d8bb52;

    // ─── EVENTS ────────────────────────────────────────────────────

    event LiquidationDetected(
        address indexed liquidatedUser,
        address indexed liquidator,
        uint256 debtAmount,
        uint256 timestamp,
        uint256 triggerCount
    );

    event ShieldActivated(
        uint256 indexed strategyId,
        uint256 timestamp
    );

    // ─── CONSTRUCTOR ───────────────────────────────────────────────

    constructor(
        address _registryAddress,
        uint256 _strategyId
    ) {
        owner = msg.sender;
        registryAddress = _registryAddress;
        strategyId = _strategyId;
        totalTriggers = 0;
    }

    // ─── THE REACTIVE HEART ────────────────────────────────────────

    /**
     * @notice Somnia calls this automatically when a
     * liquidation event fires on-chain.
     * No bot. No server. Pure on-chain reactivity.
     */
    function _onEvent(
        address emitter,
        bytes32[] calldata eventTopics,
        bytes calldata data
    ) internal override {
        // Step 1: Verify this is a liquidation event
        if (eventTopics.length == 0) return;
        if (eventTopics[0] != LIQUIDATION_TOPIC) return;

        // Step 2: Decode liquidated user and debt amount
        address liquidatedUser = address(uint160(uint256(eventTopics[1])));
        address liquidator = address(uint160(uint256(eventTopics[2])));
        uint256 debtAmount = abi.decode(data, (uint256));

        // Step 3: Record trigger
        totalTriggers++;

        // Step 4: Emit event — frontend WebSocket picks this up instantly
        emit LiquidationDetected(
            liquidatedUser,
            liquidator,
            debtAmount,
            block.timestamp,
            totalTriggers
        );

        // Step 5: Tell registry this strategy executed (updates leaderboard)
        IStrategyRegistry(registryAddress).recordExecution(strategyId);

        // Step 6: Shield activated
        emit ShieldActivated(strategyId, block.timestamp);
    }

    // ─── VIEW ──────────────────────────────────────────────────────

    function getTotalTriggers() external view returns (uint256) {
        return totalTriggers;
    }
}