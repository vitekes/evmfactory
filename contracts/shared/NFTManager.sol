// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../errors/Errors.sol";

contract NFTManager is ERC721URIStorage, Ownable {
    uint256 public tokenIdCounter;
    uint256 public constant MAX_BATCH_MINT = 50;
    mapping(uint256 => bool) public isSoulbound;

    event Minted(address indexed to, uint256 indexed tokenId, string uri, bool soulbound);

    constructor(string memory name_, string memory symbol_)
        ERC721(name_, symbol_)
        Ownable(msg.sender)
    {}

    /// @notice Выпуск NFT или SBT
    function mint(
        address to,
        string calldata uri,
        bool soulbound
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = ++tokenIdCounter;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        isSoulbound[tokenId] = soulbound;

        emit Minted(to, tokenId, uri, soulbound);
        return tokenId;
    }

    /// @notice Soulbound токены нельзя переводить
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = ERC721.ownerOf(tokenId);
        if (!(from == address(0) || to == address(0) || !isSoulbound[tokenId])) revert SbtNonTransferable();
        return super._update(to, tokenId, auth);
    }

    /// В случае чего админ может сжечь токен
    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
    }

    /// @notice Массовый выпуск NFT
    function mintBatch(address[] calldata recipients, string[] calldata uris, bool soulbound) external onlyOwner {
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
