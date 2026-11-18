// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Test double for the SPACE ID Agent ID contract. The real
///         contract is a soulbound ERC-721; AgentDirectory only ever calls
///         `balanceOf`, so that is all this mock models. `mint`/`revoke`
///         exist purely to set up test scenarios.
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function mint(address to) external {
        _balances[to] += 1;
    }

    function revoke(address account) external {
        _balances[account] = 0;
    }
}
