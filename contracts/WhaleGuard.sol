// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { SomniaEventHandler } from "@somnia-chain/reactivity-contracts/contracts/SomniaEventHandler.sol";

interface IStrategyRegistry {
    function recordExecution(uint256 strategyId) external;
    function isSubscribed(address user, uint256 strategyId) external view returns (bool);
}

/**
 * @title WhaleGuard
 * @notice This is ChainPulse's first reactive strategy.
 * It listens for large token transfers on-chain.
 * When a whale moves funds above the threshold,
 * Somnia calls _onEvent() automatically — no bot, no server.
 */
contract WhaleGuard is SomniaEventHandler {

    // ─── STATE VARIABLES ───────────────────────────────────────────

    address public owner;
    address public registryAddress;
    uint256 public strategyId;

    // Whale threshold — transfers above this amount trigger the guard
    // Set to 1000 tokens by default (in wei units)
    uint256 public whaleThreshold;

    uint256 public totalTriggers;

    // ERC20 Transfer event signature
    // keccak256("Transfer(address,address,uint256)")
    bytes32 public constant TRANSFER_TOPIC =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // ─── EVENTS ────────────────────────────────────────────────────

    // This is what the frontend WebSocket listens to
    event WhaleDetected(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp,
        uint256 triggerCount
    );

    event GuardActivated(
        address indexed protectedUser,
        uint256 indexed strategyId,
        uint256 timestamp
    );

    // ─── CONSTRUCTOR ───────────────────────────────────────────────

    constructor(
        address _registryAddress,
        uint256 _strategyId,
        uint256 _whaleThreshold
    ) {
        owner = msg.sender;
        registryAddress = _registryAddress;
        strategyId = _strategyId;
        whaleThreshold = _whaleThreshold;
        totalTriggers = 0;
    }

    // ─── MODIFIERS ─────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ─── THE REACTIVE HEART ────────────────────────────────────────

    /**
     * @notice Somnia calls this function automatically when
     * a subscribed event fires on-chain.
     *
     * @param emitter   The contract that emitted the event
     * @param eventTopics  The event topics (topic[0] = event signature)
     * @param data      The encoded event data
     *
     * This is the magic moment in your demo video.
     * No bot triggered this. No server triggered this.
     * Somnia's reactivity layer called this directly.
     */
    function _onEvent(
        address emitter,
        bytes32[] calldata eventTopics,
        bytes calldata data
    ) internal override {
        // Step 1: Make sure this is a Transfer event
        if (eventTopics.length == 0) return;
        if (eventTopics[0] != TRANSFER_TOPIC) return;

        // Step 2: Decode the transfer amount from event data
        // Transfer(address indexed from, address indexed to, uint256 value)
        // indexed params are in topics, value is in data
        uint256 transferAmount = abi.decode(data, (uint256));

        // Step 3: Check if this is a whale-level transfer
        if (transferAmount < whaleThreshold) return;

        // Step 4: Decode sender and receiver from topics
        address from = address(uint160(uint256(eventTopics[1])));
        address to = address(uint160(uint256(eventTopics[2])));

        // Step 5: Record the trigger
        totalTriggers++;

        // Step 6: Emit the event — frontend WebSocket picks this up instantly
        emit WhaleDetected(
            from,
            to,
            transferAmount,
            block.timestamp,
            totalTriggers
        );

        // Step 7: Tell the registry this strategy executed
        // This updates the leaderboard count
        IStrategyRegistry(registryAddress).recordExecution(strategyId);

        // Step 8: Activate guard for all subscribed users
        // In a full version this would execute protective actions
        // For the demo we emit GuardActivated as proof of execution
        emit GuardActivated(msg.sender, strategyId, block.timestamp);
    }

    // ─── OWNER FUNCTIONS ───────────────────────────────────────────

    /**
     * @notice Update the whale threshold
     */
    function setWhaleThreshold(uint256 newThreshold) external onlyOwner {
        whaleThreshold = newThreshold;
    }

    /**
     * @notice Update the registry address if redeployed
     */
    function setRegistryAddress(address newRegistry) external onlyOwner {
        registryAddress = newRegistry;
    }

    // ─── VIEW FUNCTIONS ────────────────────────────────────────────

    function getTotalTriggers() external view returns (uint256) {
        return totalTriggers;
    }
}