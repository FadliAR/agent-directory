// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {AgentDirectory} from "../contracts/AgentDirectory.sol";
import {MockAgentID} from "./MockAgentID.sol";

/// @notice Minimal cheatcode interface (subset of Foundry's Vm), so the
///         suite needs no external test dependency.
interface Vm {
    function prank(address msgSender) external;
    function expectRevert() external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter)
        external;
    function warp(uint256 newTimestamp) external;
}

contract AgentDirectoryTest {
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Re-declared so expectEmit can compare against emitted events.
    event CardRegistered(address indexed agent, string agentName, string category);

    MockAgentID private mockID;
    AgentDirectory private dir;

    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);
    address private carol = address(0xCA401);
    address private dave = address(0xDA9E);
    address private erin = address(0xE219);
    address private stranger = address(0x57A9); // never holds an Agent ID

    function setUp() public {
        mockID = new MockAgentID();
        dir = new AgentDirectory(address(mockID));
        mockID.mint(alice);
        mockID.mint(bob);
        mockID.mint(carol);
        mockID.mint(dave);
        mockID.mint(erin);
    }

    // ---------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------

    function _register(address who, string memory name) internal {
        vm.prank(who);
        dir.registerCard(name, "research", "I do research.", "https://example.com/agent");
    }

    function assertTrue(bool cond, string memory msg_) internal pure {
        require(cond, msg_);
    }

    function assertEq(uint256 a, uint256 b, string memory msg_) internal pure {
        require(a == b, msg_);
    }

    function assertEq(address a, address b, string memory msg_) internal pure {
        require(a == b, msg_);
    }

    function assertEq(string memory a, string memory b, string memory msg_) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), msg_);
    }

    // ---------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------

    function testConstructorSetsAgentID() public view {
        assertEq(address(dir.agentID()), address(mockID), "agentID mismatch");
    }

    function testConstructorRevertsOnZeroAddress() public {
        vm.expectRevert();
        new AgentDirectory(address(0));
    }

    // ---------------------------------------------------------------
    // Registration gating
    // ---------------------------------------------------------------

    function testHolderCanRegister() public {
        vm.expectEmit(true, false, false, true, address(dir));
        emit CardRegistered(alice, "alice.ai", "research");
        _register(alice, "alice.ai");

        assertTrue(dir.isRegistered(alice), "alice should be registered");
        assertEq(dir.totalAgents(), 1, "totalAgents should be 1");

        (string memory name, string memory category, string memory desc, string memory endpoint,,,) =
            dir.getCard(alice);
        assertEq(name, "alice.ai", "name mismatch");
        assertEq(category, "research", "category mismatch");
        assertEq(desc, "I do research.", "description mismatch");
        assertEq(endpoint, "https://example.com/agent", "endpoint mismatch");
    }

    function testNonHolderCannotRegister() public {
        vm.prank(stranger);
        vm.expectRevert();
        dir.registerCard("mallory.ai", "research", "x", "y");
    }

    function testRegisterTwiceReverts() public {
        _register(alice, "alice.ai");
        vm.prank(alice);
        vm.expectRevert();
        dir.registerCard("alice2.ai", "research", "x", "y");
    }

    function testEmptyNameReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        dir.registerCard("", "research", "x", "y");
    }

    function testOverlongFieldsRevert() public {
        string memory longDesc = new string(281); // cap is 280 bytes
        vm.prank(alice);
        vm.expectRevert();
        dir.registerCard("alice.ai", "research", longDesc, "y");

        string memory longName = new string(65); // cap is 64 bytes
        vm.prank(alice);
        vm.expectRevert();
        dir.registerCard(longName, "research", "x", "y");
    }

    // ---------------------------------------------------------------
    // Update
    // ---------------------------------------------------------------

    function testHolderCanUpdateCard() public {
        vm.warp(1_000);
        _register(alice, "alice.ai");

        vm.warp(2_000);
        vm.prank(alice);
        dir.updateCard("alice.ai", "data", "Updated description.", "https://example.com/v2");

        (string memory name, string memory category, string memory desc,, , uint64 regAt, uint64 updAt) =
            dir.getCard(alice);
        assertEq(name, "alice.ai", "name mismatch");
        assertEq(category, "data", "category mismatch");
        assertEq(desc, "Updated description.", "description mismatch");
        assertEq(uint256(regAt), 1_000, "registeredAt must not change");
        assertEq(uint256(updAt), 2_000, "updatedAt should move");
        assertEq(dir.totalAgents(), 1, "update must not duplicate the entry");
    }

    function testUpdateRevertsWhenNotRegistered() public {
        vm.prank(alice); // holds an Agent ID but has no card
        vm.expectRevert();
        dir.updateCard("alice.ai", "data", "x", "y");
    }

    function testNonHolderCannotUpdate() public {
        _register(alice, "alice.ai");
        vm.prank(stranger);
        vm.expectRevert();
        dir.updateCard("alice.ai", "data", "x", "y");
    }

    // ---------------------------------------------------------------
    // Endorsements
    // ---------------------------------------------------------------

    function testHolderCanEndorse() public {
        _register(alice, "alice.ai");
        _register(bob, "bob.ai");

        vm.prank(alice);
        dir.endorse(bob);

        assertTrue(dir.hasEndorsed(alice, bob), "endorsement flag missing");
        assertEq(dir.getEndorsementCount(bob), 1, "bob should have 1 endorsement");
        (,,,, uint256 endorsements,,) = dir.getCard(bob);
        assertEq(endorsements, 1, "getCard should report 1 endorsement");
    }

    function testNonHolderCannotEndorse() public {
        _register(bob, "bob.ai");
        vm.prank(stranger);
        vm.expectRevert();
        dir.endorse(bob);
    }

    function testEndorseSelfReverts() public {
        _register(alice, "alice.ai");
        vm.prank(alice);
        vm.expectRevert();
        dir.endorse(alice);
    }

    function testEndorseTwiceReverts() public {
        _register(alice, "alice.ai");
        _register(bob, "bob.ai");
        vm.prank(alice);
        dir.endorse(bob);
        vm.prank(alice);
        vm.expectRevert();
        dir.endorse(bob);
    }

    function testEndorseUnregisteredTargetReverts() public {
        _register(alice, "alice.ai");
        // carol holds an Agent ID but never registered a card
        vm.prank(alice);
        vm.expectRevert();
        dir.endorse(carol);
    }

    function testEndorseDeregisteredTargetReverts() public {
        _register(alice, "alice.ai");
        _register(bob, "bob.ai");
        vm.prank(bob);
        dir.deregister();
        vm.prank(alice);
        vm.expectRevert();
        dir.endorse(bob);
    }

    // ---------------------------------------------------------------
    // Deregistration
    // ---------------------------------------------------------------

    function testDeregisterRemovesCard() public {
        _register(alice, "alice.ai");
        vm.prank(alice);
        dir.deregister();

        assertTrue(!dir.isRegistered(alice), "alice should be gone");
        assertEq(dir.totalAgents(), 0, "totalAgents should be 0");
        vm.expectRevert();
        dir.getCard(alice);
    }

    function testDeregisterMiddleKeepsListIntact() public {
        _register(alice, "alice.ai");
        _register(bob, "bob.ai");
        _register(carol, "carol.ai");

        vm.prank(bob); // middle entry leaves; carol is swapped into his slot
        dir.deregister();

        assertEq(dir.totalAgents(), 2, "totalAgents should be 2");
        address[] memory page = dir.listAgents(0, 10);
        assertEq(page.length, 2, "page length should be 2");
        assertEq(page[0], alice, "slot 0 should be alice");
        assertEq(page[1], carol, "slot 1 should be carol after swap-pop");
        (string memory carolName,,,,,,) = dir.getCard(carol);
        assertEq(carolName, "carol.ai", "carol card must survive the swap");
    }

    function testDeregisterRevertsWhenNotRegistered() public {
        vm.prank(alice);
        vm.expectRevert();
        dir.deregister();
    }

    function testCanReregisterAfterDeregister() public {
        _register(alice, "alice.ai");
        vm.prank(alice);
        dir.deregister();
        _register(alice, "alice-new.ai");

        assertTrue(dir.isRegistered(alice), "alice should be back");
        (string memory name,,,,,,) = dir.getCard(alice);
        assertEq(name, "alice-new.ai", "new card should be stored");
    }

    function testDeregisterWorksEvenIfAgentIDRevoked() public {
        // Exit must always be possible: deregister is intentionally not
        // gated on still holding an Agent ID.
        _register(alice, "alice.ai");
        mockID.revoke(alice);
        vm.prank(alice);
        dir.deregister();
        assertTrue(!dir.isRegistered(alice), "alice should be able to leave");
    }

    // ---------------------------------------------------------------
    // Reads / pagination
    // ---------------------------------------------------------------

    function testPagination() public {
        _register(alice, "alice.ai");
        _register(bob, "bob.ai");
        _register(carol, "carol.ai");
        _register(dave, "dave.ai");
        _register(erin, "erin.ai");

        assertEq(dir.totalAgents(), 5, "totalAgents should be 5");
        assertEq(dir.listAgents(0, 2).length, 2, "first page");
        assertEq(dir.listAgents(2, 2).length, 2, "second page");
        assertEq(dir.listAgents(4, 2).length, 1, "last partial page");
        assertEq(dir.listAgents(5, 2).length, 0, "past the end");
        assertEq(dir.listAgents(0, 0).length, 0, "zero limit");
        assertEq(dir.listAgents(1, 1)[0], bob, "offset addressing");
    }

    function testGetCardRevertsForUnknown() public {
        vm.expectRevert();
        dir.getCard(stranger);
    }

    function testEndorsementCountZeroForUnknown() public view {
        assertEq(dir.getEndorsementCount(stranger), 0, "unknown address has 0 endorsements");
    }
}
