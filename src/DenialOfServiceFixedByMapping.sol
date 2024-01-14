// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

/// @author terrancrypt
/// @dev Contract này giúp tạo một contract sổ xố, khi người tham gia (participants) có thể nạp tiền của họ vào để tham gia vào sổ xố với mức phí được owner quy định sẵn. Chỉ một người trúng thưởng khi owner tìm ra người chiến thắng thông qua Chainlink VRF. Tiền của mọi người chơi khác nạp vào sẽ được chuyển cho người thắng cuộc.
contract DenialOfService is VRFConsumerBaseV2, Ownable {
    error DenialOfService_UnableToRejoin();
    error DenialOfService_NotEnoughFee(uint fee);
    error DenialOfService_SendingEtherError();
    error DenialOfService_RaffleNotOpen();
    error DenialOfService_NotTheWinner(address winner);
    error DenialOfService_NotEnoughParticipants(uint256 numberOfParticipants);
    error DenialOfService_DontHaveWinner();
    error DenialOfService_InsufficientBalance();

    mapping(uint256 id => address participant) private s_participants;
    uint256 private s_participantCurrentId;
    mapping(address participant => bool exists) private s_isParticipantExists;

    uint private s_participantFee; // chứa thông tin về phí tham gia của mỗi người chơi
    bool private s_isRaffleOpen; //  cho biết xổ số có đang mở để tham gia hay không

    mapping(address winner => uint256 amount) private s_winnerBalance;

    // Chainlink VRF // Để lấy số ngẫu nhiên một cách công bằng
    uint64 s_subscriptionId;
    address s_owner;
    VRFCoordinatorV2Interface COORDINATOR;
    address vrfCoordinator;

    // This key hash for Sepolia testnet
    bytes32 s_keyHash =
        0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c;
    uint32 callbackGasLimit = 100000; // giới hạn gas limit gọi lại của chainlink là bao nhiêu
    uint16 requestConfirmations = 3; // 3 node của chainlink sẽ confirm số ngẫu nhiên
    uint32 numWords = 1; // chỉ lấy một số ngẫu nhiên từ chainlink vrf

    constructor(
        address _owner,
        address _vrfCoordinator,
        uint64 _subscriptionId
    ) Ownable(_owner) VRFConsumerBaseV2(_vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        s_owner = _owner;
        s_subscriptionId = _subscriptionId;
        s_isRaffleOpen = true;
    }

    event NewParticipantsEntered(address[] participants);
    event NewParticipantEntered(address participant);
    event LookingForAWinner(uint256 requestId);
    event GetTheWinner(uint256 requestId, address winner);
    event WinnerPrizeClaimed(address winner, uint256 prize);
    event SentPrizeToWinner(address winner, uint256 prize);

    function setFee(uint _fee) public onlyOwner {
        s_participantFee = _fee;
    }

    function enterRaffle(address[] memory newParticipants) public payable {
        if (!s_isRaffleOpen) {
            revert DenialOfService_RaffleNotOpen();
        }

        if (msg.value != s_participantFee * newParticipants.length) {
            revert DenialOfService_NotEnoughFee(
                s_participantFee * newParticipants.length
            );
        }

        // DOS: unbounded for loop
        for (uint256 i; i < newParticipants.length; i++) {
            if (s_isParticipantExists[newParticipants[i]] == true) {
                revert DenialOfService_UnableToRejoin();
            }

            s_participants[s_participantCurrentId] = newParticipants[i];
            s_participantCurrentId++;
            s_isParticipantExists[newParticipants[i]] = true;
        }

        emit NewParticipantsEntered(newParticipants);
    }

    function enterRaffleSingle(address newParticipant) public payable {
        if (!s_isRaffleOpen) {
            revert DenialOfService_RaffleNotOpen();
        }

        if (msg.value != s_participantFee) {
            revert DenialOfService_NotEnoughFee(s_participantFee);
        }

        if (s_isParticipantExists[newParticipant] == true) {
            revert DenialOfService_UnableToRejoin();
        }

        s_participants[s_participantCurrentId] = newParticipant;
        s_participantCurrentId++;
        s_isParticipantExists[newParticipant] = true;

        emit NewParticipantEntered(newParticipant);
    }

    function getWinner() public onlyOwner returns (uint256 requestId) {
        if (s_participantCurrentId < 10) {
            revert DenialOfService_NotEnoughParticipants(
                s_participantCurrentId
            );
        }

        requestId = COORDINATOR.requestRandomWords(
            s_keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );

        s_isRaffleOpen = false;

        emit LookingForAWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        if (s_isRaffleOpen) {
            revert DenialOfService_RaffleNotOpen();
        }
        uint256 randomValue = (randomWords[0] % s_participantCurrentId) + 1;
        address winner = s_participants[randomValue];
        uint256 prize = s_participantCurrentId * s_participantFee;

        s_winnerBalance[winner] = prize;
        s_isRaffleOpen = true;
        delete s_participantCurrentId;

        emit GetTheWinner(requestId, winner);
    }

    // dos: external call failing (push / pull)
    function claimPrize() public {
        uint256 balance = s_winnerBalance[msg.sender];
        if (balance <= 0) {
            revert DenialOfService_InsufficientBalance();
        }

        s_winnerBalance[msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: balance}("");

        if (!sent) {
            revert DenialOfService_SendingEtherError();
        }

        emit WinnerPrizeClaimed(msg.sender, balance);
    }

    function getParticipantFee() public view returns (uint) {
        return s_participantFee;
    }
}

contract AttackDenialOfService {
    DenialOfService immutable i_target;

    constructor(address _target) {
        i_target = DenialOfService(_target);
    }

    function deposit() public payable {}

    function attack() public {
        uint fee = i_target.getParticipantFee();
        i_target.enterRaffleSingle{value: fee}(address(this));
    }
}
