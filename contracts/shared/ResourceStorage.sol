// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ResourceStorage is Ownable {
    constructor() Ownable(msg.sender) {}

    struct Resource {
        string key;     // например: "title", "description", "image", "config"
        string value;   // IPFS-хеш, URL, markdown, JSON и т.д.
    }

    // itemId => хеш ключа => Resource
    mapping(uint256 => mapping(bytes32 => Resource)) private resources;
    // itemId => список хешей ключей для enumeration
    mapping(uint256 => bytes32[]) private resourceKeys;

    event ResourceSet(uint256 indexed itemId, string key, string value);
    event ResourceCleared(uint256 indexed itemId);

    /// Установить или обновить ресурс
    function setResource(uint256 itemId, string calldata key, string calldata value) external onlyOwner {
        bytes32 k = keccak256(bytes(key));
        if (bytes(resources[itemId][k].key).length == 0) {
            resourceKeys[itemId].push(k);
        }
        resources[itemId][k] = Resource({key: key, value: value});
        emit ResourceSet(itemId, key, value);
    }

    /// Получить ресурс по ключу
    function getResource(uint256 itemId, string calldata key) external view returns (string memory) {
        return resources[itemId][keccak256(bytes(key))].value;
    }

    /// Получить весь список ресурсов
    function getAllResources(uint256 itemId) external view returns (Resource[] memory) {
        bytes32[] storage keys = resourceKeys[itemId];
        Resource[] memory list = new Resource[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            list[i] = resources[itemId][keys[i]];
        }
        return list;
    }

    /// Очистить все ресурсы у item
    function clearResources(uint256 itemId) external onlyOwner {
        bytes32[] storage keys = resourceKeys[itemId];
        for (uint256 i = 0; i < keys.length; i++) {
            delete resources[itemId][keys[i]];
        }
        delete resourceKeys[itemId];
        emit ResourceCleared(itemId);
    }
}
