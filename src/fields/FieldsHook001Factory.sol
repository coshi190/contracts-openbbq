// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./FieldsHook001.sol";

contract FieldsHook001Factory {
    IOpenBbqFieldsV2Router public openBbqFieldsV2Router;

    struct PeripheryMetadata { // partial mutable, can collect fees
        string name;
        string description;
        string banner;
        string cover;
        uint256 createdTime;
        address creator;
    }
    mapping(uint256 => PeripheryMetadata) public peripheryMetadata;

    event CreatePeriphery(uint256 indexed peripheryIndexOnRouter, address indexed peripheryAddress, address indexed peripheryOwner);
    event SetPeripheryMetadata(uint256 indexed peripheryIndexOnRouter, string name, string description, string banner, string cover);

    constructor(address _openBbqFieldsV2Router) {
        openBbqFieldsV2Router = IOpenBbqFieldsV2Router(_openBbqFieldsV2Router);
        openBbqFieldsV2Router.setHook(address(this));
    }

    function createPeriphery(address _peripheryOwner, uint256 _baseHashRate) external payable { // can collect fees and/or provide incentives to adopt future hooks
        require(msg.value == openBbqFieldsV2Router.feeForCreatePeriphery().feeAmount, "inadequate for the creation fee");
        
        uint256 _peripheryIndexOnRouter = openBbqFieldsV2Router.peripheryCount() + 1;
        FieldsHook001 newPeriphery = new FieldsHook001(_peripheryIndexOnRouter, _baseHashRate, address(openBbqFieldsV2Router));
        openBbqFieldsV2Router.setPeriphery{value: openBbqFieldsV2Router.feeForCreatePeriphery().feeAmount}(address(newPeriphery), _peripheryOwner);
        peripheryMetadata[_peripheryIndexOnRouter].createdTime = block.timestamp;
        peripheryMetadata[_peripheryIndexOnRouter].creator = msg.sender;

        emit CreatePeriphery(_peripheryIndexOnRouter, address(newPeriphery), _peripheryOwner);
    }

    function setPeripheryMetadata(
        uint256 _peripheryIndex,
        string memory _name,
        string memory _description,
        string memory _banner,
        string memory _cover
    ) external {
        require(openBbqFieldsV2Router.peripheryOwner(_peripheryIndex) == msg.sender, "not peripheryOwner");

        peripheryMetadata[_peripheryIndex].name = _name;
        peripheryMetadata[_peripheryIndex].description = _description;
        peripheryMetadata[_peripheryIndex].banner = _banner;
        peripheryMetadata[_peripheryIndex].cover = _cover;

        emit SetPeripheryMetadata(_peripheryIndex, _name, _description, _banner, _cover);
    }
}
