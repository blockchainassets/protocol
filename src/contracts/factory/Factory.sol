pragma solidity ^0.4.21;


contract Factory {
    mapping (address => bool) public childExists;

    event NewInstance(
        address indexed hub,
        address indexed instance
    );

    function isInstance(address _child) public returns (bool) {
        return childExists[_child];
    }

    // function createInstance() returns (address);
}

