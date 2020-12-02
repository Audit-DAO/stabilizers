// SPDX-License-Identifier: MIT
pragma solidity >=0.6.6;

import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract RandomNumberConsumer is VRFConsumerBase {
    bytes32 internal keyHash;
    uint256 internal fee;

    address public multiSigSafe;
    address public randomizedCounter;

    uint256 public randomResult;

    constructor(
        address VRFCoordinator,
        address LINK,
        address multiSigSafe_,
        address randomizedCounter_
    )
        public
        VRFConsumerBase(
            VRFCoordinator, // VRF Coordinator
            LINK // LINK Token
        )
    {
        keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
        fee = 0.1 * 10**18; // 0.1 LINK
        multiSigSafe = multiSigSafe_;
        randomizedCounter = randomizedCounter_;
    }

    /**
     * Requests randomness from a user-provided seed
     */
    function getRandomNumber(uint256 userProvidedSeed)
        public
        returns (bytes32 requestId)
    {
        require(
            msg.sender == randomizedCounter,
            "Only counter can call this function"
        );
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        return requestRandomness(keyHash, fee, userProvidedSeed);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;
    }

    function withdrawLink() external {
        require(
            msg.sender == multiSigSafe,
            "Only multi sig safe can withdraw link"
        );
        require(
            LINK.transfer(msg.sender, LINK.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
