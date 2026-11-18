// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal read interface for the SPACE ID Agent ID contract
///         (BNB Chain: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
///         The directory only ever READS `balanceOf`; it never calls any
///         state-changing function on the Agent ID contract.
interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
}

/// @title AgentDirectory
/// @notice An opt-in, on-chain registry where Agent ID holders publish a
///         public service/profile card for their agent, so other agents and
///         users can discover who offers what.
///
///         Design constraints (deliberate, and part of the security story):
///         - No token, no payments, no value handling: the contract is
///           non-payable and can never hold or move any asset.
///         - No approvals: the only external call is a read-only
///           `balanceOf` on the Agent ID contract.
///         - No owner, no admin, no pause, no upgrade path. The Agent ID
///           contract address is set once in the constructor and is
///           immutable.
///         - Every write is gated on the caller holding an Agent ID
///           (`balanceOf(caller) > 0` on the real Agent ID contract).
///         - Opt-in only: the directory shows nothing about anyone who has
///           not registered themselves, and anyone can erase their own
///           card at any time with `deregister()`.
contract AgentDirectory {
    /// @notice The Agent ID contract whose holders may use this directory.
    IAgentID public immutable agentID;

    // Field length caps (in bytes) keep cards small, cheap and readable.
    uint256 public constant MAX_NAME_LENGTH = 64;
    uint256 public constant MAX_CATEGORY_LENGTH = 32;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 280;
    uint256 public constant MAX_ENDPOINT_LENGTH = 128;

    struct Card {
        string agentName; // the holder's .ai name, self-declared
        string category; // e.g. "research", "trading-tools", "art"
        string description; // short public description of the service
        string endpoint; // contact / endpoint string (URL, handle, ...)
        uint64 registeredAt;
        uint64 updatedAt;
    }

    mapping(address => Card) private _cards;
    mapping(address => bool) public isRegistered;

    // Registered addresses, kept as an array for pagination. _indexPlusOne
    // stores (index + 1) so 0 means "not in the list".
    address[] private _agents;
    mapping(address => uint256) private _indexPlusOne;

    /// @notice hasEndorsed[a][b] is true once a has endorsed b (one per pair).
    mapping(address => mapping(address => bool)) public hasEndorsed;
    /// @notice Total endorsements received by an address. Endorsements are
    ///         historical: deregistering does not rewrite them, so counts
    ///         and hasEndorsed flags stay consistent if an agent returns.
    mapping(address => uint256) public endorsementCount;

    event CardRegistered(address indexed agent, string agentName, string category);
    event CardUpdated(address indexed agent);
    event CardDeregistered(address indexed agent);
    event Endorsed(address indexed from, address indexed to);

    constructor(address agentID_) {
        require(agentID_ != address(0), "AgentDirectory: zero address");
        agentID = IAgentID(agentID_);
    }

    modifier onlyAgent() {
        require(agentID.balanceOf(msg.sender) > 0, "AgentDirectory: no Agent ID");
        _;
    }

    // ------------------------------------------------------------------
    // Writes (all Agent-ID-gated)
    // ------------------------------------------------------------------

    /// @notice Publish your card. Caller must hold an Agent ID and must not
    ///         already be registered (use `updateCard` to change a card).
    function registerCard(
        string calldata agentName,
        string calldata category,
        string calldata description,
        string calldata endpoint
    ) external onlyAgent {
        require(!isRegistered[msg.sender], "AgentDirectory: already registered");
        _validate(agentName, category, description, endpoint);

        Card storage c = _cards[msg.sender];
        c.agentName = agentName;
        c.category = category;
        c.description = description;
        c.endpoint = endpoint;
        c.registeredAt = uint64(block.timestamp);
        c.updatedAt = uint64(block.timestamp);

        isRegistered[msg.sender] = true;
        _agents.push(msg.sender);
        _indexPlusOne[msg.sender] = _agents.length; // index + 1

        emit CardRegistered(msg.sender, agentName, category);
    }

    /// @notice Replace the contents of your existing card.
    function updateCard(
        string calldata agentName,
        string calldata category,
        string calldata description,
        string calldata endpoint
    ) external onlyAgent {
        require(isRegistered[msg.sender], "AgentDirectory: not registered");
        _validate(agentName, category, description, endpoint);

        Card storage c = _cards[msg.sender];
        c.agentName = agentName;
        c.category = category;
        c.description = description;
        c.endpoint = endpoint;
        c.updatedAt = uint64(block.timestamp);

        emit CardUpdated(msg.sender);
    }

    /// @notice Remove your card and leave the directory. Endorsements you
    ///         gave and received are historical and are not rewritten.
    function deregister() external {
        require(isRegistered[msg.sender], "AgentDirectory: not registered");

        // Swap-and-pop keeps the list compact and pagination stable.
        uint256 index = _indexPlusOne[msg.sender] - 1;
        uint256 lastIndex = _agents.length - 1;
        if (index != lastIndex) {
            address moved = _agents[lastIndex];
            _agents[index] = moved;
            _indexPlusOne[moved] = index + 1;
        }
        _agents.pop();
        delete _indexPlusOne[msg.sender];

        isRegistered[msg.sender] = false;
        delete _cards[msg.sender];

        emit CardDeregistered(msg.sender);
    }

    /// @notice Endorse another registered agent. Caller must hold an
    ///         Agent ID; one endorsement per (endorser, target) pair;
    ///         self-endorsement is not allowed.
    function endorse(address target) external onlyAgent {
        require(target != msg.sender, "AgentDirectory: cannot endorse self");
        require(isRegistered[target], "AgentDirectory: target not registered");
        require(!hasEndorsed[msg.sender][target], "AgentDirectory: already endorsed");

        hasEndorsed[msg.sender][target] = true;
        endorsementCount[target] += 1;

        emit Endorsed(msg.sender, target);
    }

    // ------------------------------------------------------------------
    // Reads (open to everyone; used by the directory frontend/indexers)
    // ------------------------------------------------------------------

    /// @notice Number of agents currently in the directory.
    function totalAgents() external view returns (uint256) {
        return _agents.length;
    }

    /// @notice Full card for a registered agent, plus endorsements received.
    function getCard(address agent)
        external
        view
        returns (
            string memory agentName,
            string memory category,
            string memory description,
            string memory endpoint,
            uint256 endorsements,
            uint64 registeredAt,
            uint64 updatedAt
        )
    {
        require(isRegistered[agent], "AgentDirectory: not registered");
        Card storage c = _cards[agent];
        return (
            c.agentName,
            c.category,
            c.description,
            c.endpoint,
            endorsementCount[agent],
            c.registeredAt,
            c.updatedAt
        );
    }

    /// @notice A page of registered addresses: entries
    ///         [offset, offset + limit), clamped to the list length.
    function listAgents(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 total = _agents.length;
        if (offset >= total || limit == 0) {
            return new address[](0);
        }
        uint256 count = total - offset;
        if (count > limit) count = limit;
        page = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            page[i] = _agents[offset + i];
        }
    }

    /// @notice Endorsements received by an address (0 if none / unknown).
    function getEndorsementCount(address agent) external view returns (uint256) {
        return endorsementCount[agent];
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _validate(
        string calldata agentName,
        string calldata category,
        string calldata description,
        string calldata endpoint
    ) internal pure {
        require(bytes(agentName).length > 0, "AgentDirectory: empty name");
        require(bytes(agentName).length <= MAX_NAME_LENGTH, "AgentDirectory: name too long");
        require(bytes(category).length <= MAX_CATEGORY_LENGTH, "AgentDirectory: category too long");
        require(bytes(description).length <= MAX_DESCRIPTION_LENGTH, "AgentDirectory: description too long");
        require(bytes(endpoint).length <= MAX_ENDPOINT_LENGTH, "AgentDirectory: endpoint too long");
    }
}
