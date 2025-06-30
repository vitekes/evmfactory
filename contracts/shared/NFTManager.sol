// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '../errors/Errors.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

contract NFTManager is ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 public tokenIdCounter;
    uint256 public constant MAX_BATCH_MINT = 50;
    mapping(uint256 => bool) public isSoulbound;

    event Minted(address indexed to, uint256 indexed tokenId, string uri, bool soulbound);

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) Ownable(msg.sender) {}

    /// @notice Mint an NFT or SBT
    /// @param to Recipient address
    /// @param uri Token metadata URI
    /// @param soulbound Whether token is soulbound
    /// @return tokenId Newly minted token id
    function mint(address to, string calldata uri, bool soulbound) external onlyOwner nonReentrant returns (uint256) {
        uint256 tokenId = ++tokenIdCounter;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        isSoulbound[tokenId] = soulbound;

        emit Minted(to, tokenId, uri, soulbound);
        return tokenId;
    }

    /// @notice Soulbound tokens are non-transferable
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (!(from == address(0) || to == address(0) || !isSoulbound[tokenId])) revert SbtNonTransferable();
        return super._update(to, tokenId, auth);
    }

    /// @notice Admin can burn a token if needed
    /// @param tokenId Token id to burn
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /// @notice Batch mint NFTs
    /// @param recipients Addresses receiving tokens
    /// @param uris Metadata URIs
    /// @param soulbound Whether minted tokens are soulbound
    function mintBatch(address[] calldata recipients, string[] calldata uris, bool soulbound) external onlyOwner nonReentrant {
        if (recipients.length != uris.length) revert LengthMismatch();
        if (recipients.length > MAX_BATCH_MINT) revert BatchTooLarge();
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 id = ++tokenIdCounter;
            _safeMint(recipients[i], id);
            _setTokenURI(id, uris[i]);
            isSoulbound[id] = soulbound;
            emit Minted(recipients[i], id, uris[i], soulbound);
        }
    }
}
