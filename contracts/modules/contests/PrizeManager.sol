// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./shared/PrizeInfo.sol";
import "/core/AccessControlCenter.sol";
import "./interfaces/IPrizeManager.sol";

/// @title PrizeManager
/// @notice Управляет шаблонами призовых слотов: хранит, возвращает, позволяет администраторам добавлять и обновлять
contract PrizeManager is IPrizeManager {
    AccessControlCenter public immutable acl;
    uint256 private nextTemplateId = 1;

    struct Template {
        PrizeInfo[] slots;
        string description;
    }

    mapping(uint256 => Template) private templates;

    // Роль, дающая право управлять шаблонами призов
    bytes32 public constant TEMPLATE_ADMIN = keccak256("TEMPLATE_ADMIN");

    constructor(address _acl) {
        acl = AccessControlCenter(_acl);
    }

    function addTemplate(
        PrizeInfo[] calldata slots,
        string calldata description
    ) external override returns (uint256 templateId) {
        require(acl.hasRole(TEMPLATE_ADMIN, msg.sender), "Not TEMPLATE_ADMIN");

        templateId = nextTemplateId++;
        Template storage t = templates[templateId];
        t.description = description;
        for (uint i = 0; i < slots.length; i++) {
            t.slots.push(slots[i]);
        }
    }

    function updateTemplate(
        uint256 templateId,
        PrizeInfo[] calldata slots,
        string calldata description
    ) external override {
        require(acl.hasRole(TEMPLATE_ADMIN, msg.sender), "Not TEMPLATE_ADMIN");
        require(templateId > 0 && templateId < nextTemplateId, "Invalid templateId");

        Template storage t = templates[templateId];
        t.description = description;
        delete t.slots;
        for (uint i = 0; i < slots.length; i++) {
            t.slots.push(slots[i]);
        }
    }

    function getTemplate(
        uint256 templateId
    ) external view override returns (
        PrizeInfo[] memory slots,
        string memory description
    ) {
        require(templateId > 0 && templateId < nextTemplateId, "Invalid templateId");
        Template storage t = templates[templateId];
        return (t.slots, t.description);
    }
}
