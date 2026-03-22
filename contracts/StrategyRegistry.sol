// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title StrategyRegistry
 * @notice This is the backbone of ChainPulse.
 * It stores all strategies, tracks subscribers,
 * and handles Commit Mode (the HoldFirm mechanic).
 */
contract StrategyRegistry {

    // ─── STRUCTS ───────────────────────────────────────────────────

    struct Strategy {
        uint256 id;
        string name;
        string description;
        string category;          // "DeFi", "Whale", "Price"
        address creator;
        address handlerContract;  // the reactive contract address
        uint256 subscriberCount;
        uint256 executionCount;   // incremented every time _onEvent fires
        uint256 successCount;     // for leaderboard ranking
        bool isActive;
    }

    struct CommitInfo {
        bool isCommitted;
        uint256 unlockTime;       // timestamp when they can exit freely
        uint256 deposit;          // STT locked during commit mode
    }

    // ─── STATE VARIABLES ───────────────────────────────────────────

    address public owner;
    uint256 public strategyCount;
    uint256 public penaltyPool;   // accumulated penalties (jackpot)
    uint256 public constant COMMIT_PENALTY_PERCENT = 10; // 10% penalty for early exit

    // strategyId => Strategy
    mapping(uint256 => Strategy) public strategies;

    // user => strategyId => isSubscribed
    mapping(address => mapping(uint256 => bool)) public subscriptions;

    // user => strategyId => CommitInfo
    mapping(address => mapping(uint256 => CommitInfo)) public commitInfo;

    // handler contract address => strategyId (so handler can update counts)
    mapping(address => uint256) public handlerToStrategyId;

    // ─── EVENTS ────────────────────────────────────────────────────

    event StrategyPublished(uint256 indexed id, address indexed creator, string name);
    event UserSubscribed(address indexed user, uint256 indexed strategyId);
    event UserUnsubscribed(address indexed user, uint256 indexed strategyId);
    event CommitModeActivated(address indexed user, uint256 indexed strategyId, uint256 unlockTime);
    event EarlyExitPenalty(address indexed user, uint256 indexed strategyId, uint256 penalty);
    event StrategyExecuted(uint256 indexed strategyId, uint256 newExecutionCount);

    // ─── CONSTRUCTOR ───────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── MODIFIERS ─────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier strategyExists(uint256 strategyId) {
        require(strategyId > 0 && strategyId <= strategyCount, "Strategy does not exist");
        _;
    }

    // ─── PUBLISH STRATEGY ──────────────────────────────────────────

    /**
     * @notice Owner publishes a pre-built strategy to the marketplace
     * @param name Strategy name e.g. "WhaleGuard"
     * @param description What it does
     * @param category "DeFi", "Whale", "Price"
     * @param handlerContract The deployed reactive contract address
     */
    function publishStrategy(
        string memory name,
        string memory description,
        string memory category,
        address handlerContract
    ) external onlyOwner {
        strategyCount++;

        strategies[strategyCount] = Strategy({
            id: strategyCount,
            name: name,
            description: description,
            category: category,
            creator: msg.sender,
            handlerContract: handlerContract,
            subscriberCount: 0,
            executionCount: 0,
            successCount: 0,
            isActive: true
        });

        handlerToStrategyId[handlerContract] = strategyCount;

        emit StrategyPublished(strategyCount, msg.sender, name);
    }

    // ─── SUBSCRIBE ─────────────────────────────────────────────────

    /**
     * @notice Subscribe to a strategy (normal mode, free exit anytime)
     */
    function subscribe(uint256 strategyId) 
        external 
        strategyExists(strategyId) 
    {
        require(strategies[strategyId].isActive, "Strategy not active");
        require(!subscriptions[msg.sender][strategyId], "Already subscribed");

        subscriptions[msg.sender][strategyId] = true;
        strategies[strategyId].subscriberCount++;

        emit UserSubscribed(msg.sender, strategyId);
    }

    // ─── COMMIT MODE ───────────────────────────────────────────────

    /**
     * @notice Subscribe with Commit Mode — lock yourself in for X days
     * Exiting early costs a 10% penalty on your deposit
     * @param strategyId The strategy to commit to
     * @param lockDays How many days to lock in (minimum 1)
     */
    function subscribeWithCommitMode(uint256 strategyId, uint256 lockDays)
        external
        payable
        strategyExists(strategyId)
    {
        require(strategies[strategyId].isActive, "Strategy not active");
        require(!subscriptions[msg.sender][strategyId], "Already subscribed");
        require(lockDays >= 1, "Minimum 1 day lock");
        require(msg.value > 0, "Must deposit STT to activate Commit Mode");

        subscriptions[msg.sender][strategyId] = true;
        strategies[strategyId].subscriberCount++;

        uint256 unlockTime = block.timestamp + (lockDays * 1 days);

        commitInfo[msg.sender][strategyId] = CommitInfo({
            isCommitted: true,
            unlockTime: unlockTime,
            deposit: msg.value
        });

        emit UserSubscribed(msg.sender, strategyId);
        emit CommitModeActivated(msg.sender, strategyId, unlockTime);
    }

    // ─── UNSUBSCRIBE ───────────────────────────────────────────────

    /**
     * @notice Unsubscribe from a strategy
     * If in Commit Mode and exiting early, you pay a 10% penalty
     */
    function unsubscribe(uint256 strategyId)
        external
        strategyExists(strategyId)
    {
        require(subscriptions[msg.sender][strategyId], "Not subscribed");

        CommitInfo storage info = commitInfo[msg.sender][strategyId];

        // Check if user is in Commit Mode
        if (info.isCommitted) {
            if (block.timestamp < info.unlockTime) {
                // Early exit — apply penalty
                uint256 penalty = (info.deposit * COMMIT_PENALTY_PERCENT) / 100;
                uint256 refund = info.deposit - penalty;

                penaltyPool += penalty;
                info.deposit = 0;
                info.isCommitted = false;

                // Refund the rest
                if (refund > 0) {
                    payable(msg.sender).transfer(refund);
                }

                emit EarlyExitPenalty(msg.sender, strategyId, penalty);
            } else {
                // Lock period over — full refund
                uint256 refund = info.deposit;
                info.deposit = 0;
                info.isCommitted = false;

                if (refund > 0) {
                    payable(msg.sender).transfer(refund);
                }
            }
        }

        subscriptions[msg.sender][strategyId] = false;
        strategies[strategyId].subscriberCount--;

        emit UserUnsubscribed(msg.sender, strategyId);
    }

    // ─── RECORD EXECUTION (called by handler contracts) ────────────

    /**
     * @notice Called by WhaleGuard/LiquidationShield/DipBuyer
     * when _onEvent fires — updates execution count for leaderboard
     */
    function recordExecution(uint256 strategyId) external strategyExists(strategyId) {
        require(
            msg.sender == strategies[strategyId].handlerContract,
            "Only handler contract can record execution"
        );

        strategies[strategyId].executionCount++;
        strategies[strategyId].successCount++;

        emit StrategyExecuted(strategyId, strategies[strategyId].executionCount);
    }

    // ─── VIEW FUNCTIONS ────────────────────────────────────────────

    function getStrategy(uint256 strategyId) 
        external 
        view 
        returns (Strategy memory) 
    {
        return strategies[strategyId];
    }

    function isSubscribed(address user, uint256 strategyId) 
        external 
        view 
        returns (bool) 
    {
        return subscriptions[user][strategyId];
    }

    function getCommitInfo(address user, uint256 strategyId)
        external
        view
        returns (CommitInfo memory)
    {
        return commitInfo[user][strategyId];
    }

    function getAllStrategies() 
        external 
        view 
        returns (Strategy[] memory) 
    {
        Strategy[] memory all = new Strategy[](strategyCount);
        for (uint256 i = 1; i <= strategyCount; i++) {
            all[i - 1] = strategies[i];
        }
        return all;
    }

    // ─── OWNER FUNCTIONS ───────────────────────────────────────────

    /**
     * @notice Seed execution history for demo purposes
     * Makes the leaderboard look real on day one
     */
    function seedExecutionData(uint256 strategyId, uint256 execCount, uint256 succCount)
        external
        onlyOwner
        strategyExists(strategyId)
    {
        strategies[strategyId].executionCount = execCount;
        strategies[strategyId].successCount = succCount;
    }

    receive() external payable {}
}