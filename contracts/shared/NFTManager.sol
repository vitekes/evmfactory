// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTManager is ERC721URIStorage, Ownable {
    uint256 public tokenIdCounter;
    mapping(uint256 => bool) public isSoulbound;

    event Minted(address indexed to, uint256 indexed tokenId, string uri, bool soulbound);

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    /// @notice Выпуск NFT или SBT
    function mint(
        address to,
        string calldata uri,
        bool soulbound
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = ++tokenIdCounter;
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
        isSoulbound[tokenId] = soulbound;

        emit Minted(to, tokenId, uri, soulbound);
        return tokenId;
    }

    /// @notice Soulbound токены нельзя переводить
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        require(!isSoulbound[tokenId] || from == address(0), "SBT is non-transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /// В случае чего админ может сжечь токен
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /// @notice Массовый выпуск NFT
    function mintBatch(address[] calldata recipients, string[] calldata uris, bool soulbound) external onlyOwner {
        require(recipients.length == uris.length, "length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 id = ++tokenIdCounter;
            _mint(recipients[i], id);
            _setTokenURI(id, uris[i]);
            isSoulbound[id] = soulbound;
            emit Minted(recipients[i], id, uris[i], soulbound);
        }
    }
}
