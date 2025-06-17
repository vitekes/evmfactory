// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ResourceStorage is Ownable {
    constructor() Ownable(msg.sender) {}

    struct Resource {
        string key;     // например: "title", "description", "image", "config"
        string value;   // IPFS-хеш, URL, markdown, JSON и т.д.
    }

    // itemId => список ресурсов
    mapping(uint256 => Resource[]) private resources;

    event ResourceSet(uint256 indexed itemId, string key, string value);
    event ResourceCleared(uint256 indexed itemId);

    /// Установить или обновить ресурс
    function setResource(uint256 itemId, string calldata key, string calldata value) external onlyOwner {
        Resource[] storage list = resources[itemId];
        bool found;

        for (uint256 i = 0; i < list.length; i++) {
            if (keccak256(bytes(list[i].key)) == keccak256(bytes(key))) {
                list[i].value = value;
                found = true;
                break;
            }
        }

        if (!found) {
            list.push(Resource({key: key, value: value}));
        }

        emit ResourceSet(itemId, key, value);
    }

    /// Получить ресурс по ключу
    function getResource(uint256 itemId, string calldata key) external view returns (string memory) {
        Resource[] storage list = resources[itemId];

        for (uint256 i = 0; i < list.length; i++) {
            if (keccak256(bytes(list[i].key)) == keccak256(bytes(key))) {
                return list[i].value;
            }
        }

        return "";
    }

    /// Получить весь список ресурсов
    function getAllResources(uint256 itemId) external view returns (Resource[] memory) {
        return resources[itemId];
    }

    /// Очистить все ресурсы у item
    function clearResources(uint256 itemId) external onlyOwner {
        delete resources[itemId];
        emit ResourceCleared(itemId);
    }
}
