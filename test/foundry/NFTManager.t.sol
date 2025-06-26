// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {NFTManager} from "contracts/shared/NFTManager.sol";

contract NFTManagerTest is Test {
    NFTManager internal nft;
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    address internal user = address(0xABCD);
    address internal other = address(0xDCBA);

    function setUp() public {
        nft = new NFTManager("Demo", "D");
    }

    function testMintAndBurn() public {
        vm.expectEmit(true, true, true, true);
        emit NFTManager.Minted(user, 1, "uri", false);
        uint256 id = nft.mint(user, "uri", false);
        assertEq(id, 1);
        assertEq(nft.balanceOf(user), 1);

        vm.expectEmit(true, true, true, false);
        emit Transfer(user, address(0), id);
        nft.burn(id);
        assertEq(nft.balanceOf(user), 0);
    }

    function testTransferWithoutApproval() public {
        uint256 id = nft.mint(user, "u", false);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSignature("ERC721InsufficientApproval(address,uint256)", other, id));
        nft.transferFrom(user, other, id);
    }
}
