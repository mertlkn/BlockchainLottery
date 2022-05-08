// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TurkishLira.sol";
contract Lottery is ERC721 {

    struct Ticket {
        uint256 ticketNo;
        address owner;
        bytes32 hash_rnd_number;
        uint rnd_number;
        uint256 lotteryId;
        bool revealed;
        bool refunded;
        uint prize;
        bool collected;
    }

    struct Round {
        uint lotteryNo;
        uint firstTicketNo;
        Ticket[] tickets;
    }

    mapping(address => uint256) public balances;
    TurkishLira _turkishLira;
    uint256 lastTicketId;
    uint256 currentLotteryId;
    uint purchaseDeadline;
    uint revealDeadline;
    mapping(uint => uint) public amountCollectedOfLottery;
    mapping(uint => Round) public rounds;
    uint initTime;
    uint purchasePeriod = 0.5 minutes;
    uint revealPeriod = 0.5 minutes;

    constructor(TurkishLira turkishLira) ERC721("Lottery","Ltry") {
        _turkishLira = turkishLira;
        lastTicketId = 1;
        currentLotteryId = 0;
        rounds[0].firstTicketNo = lastTicketId;
        rounds[0].lotteryNo = currentLotteryId;
        purchaseDeadline = block.timestamp + purchasePeriod;
        revealDeadline = purchaseDeadline + revealPeriod;
        amountCollectedOfLottery[currentLotteryId] = 0;
        initTime = block.timestamp;
    }

    modifier revealPhase {
      require(block.timestamp > purchaseDeadline && block.timestamp < revealDeadline);
      _;
    }

    modifier balance {
      require(balances[msg.sender] < 10);
      _;
    }

    modifier purchasePhase {
        require(block.timestamp < purchaseDeadline);
        _;
    }

    modifier newRound {
        if(block.timestamp > revealDeadline) {
            uint lottery_no = getLotteryNo(block.timestamp) - 1;
            determineWinningNumber(currentLotteryId + 1);
            currentLotteryId = lottery_no;
            purchaseDeadline = initTime + currentLotteryId * (purchasePeriod + revealPeriod) + purchasePeriod;
            revealDeadline = purchaseDeadline + revealPeriod;
        }
        _;
    }

    function depositTL(uint amnt) public newRound {
        if(_turkishLira.transferFrom(msg.sender,address(this),amnt)) {
            balances[msg.sender] += amnt;
        }
    }

    function withdrawTL(uint amnt) public newRound {
        if(balances[msg.sender]>amnt){
            _turkishLira.approve(address(this), amnt);
            _turkishLira.transferFrom(address(this),msg.sender,amnt);
            balances[msg.sender] -= amnt;
        }
    }

    function buyTicket(bytes32 hash_rnd_number) public newRound purchasePhase {
        Ticket memory newTicket = Ticket(lastTicketId,msg.sender,hash_rnd_number,0,currentLotteryId,false,false,0,false);
        rounds[currentLotteryId].tickets.push(newTicket);
        _safeMint(msg.sender, lastTicketId);
        lastTicketId += 1;
        balances[msg.sender] -= 10;
        amountCollectedOfLottery[currentLotteryId] += 10;
    }

    function collectTicketRefund(uint ticket_no) public newRound purchasePhase {
        _burn(ticket_no);
        balances[msg.sender] += 5;
        uint firstTicketNo = rounds[currentLotteryId].firstTicketNo;
        rounds[currentLotteryId].tickets[ticket_no-firstTicketNo].refunded = true;
        amountCollectedOfLottery[currentLotteryId] -= 10; // refund 5 but keep 5 for the contract?
    }

    function revealRndNumber(uint ticketno, uint rnd_number) public newRound revealPhase{
        if(ownerOf(ticketno) != msg.sender) {
            revert();
        }
        bytes32 keccak=keccak256(abi.encodePacked(msg.sender,rnd_number));
        uint firstTicketNo = rounds[currentLotteryId].firstTicketNo;
        if(rounds[currentLotteryId].tickets[ticketno-firstTicketNo].hash_rnd_number != keccak) {
            revert();
        }
        rounds[currentLotteryId].tickets[ticketno-firstTicketNo].rnd_number = rnd_number;
        rounds[currentLotteryId].tickets[ticketno-firstTicketNo].revealed = true;
    }

    function getLastOwnedTicketNo(uint lottery_no) public view returns(uint,uint8 status) {
        lottery_no--;
        uint i = rounds[lottery_no].tickets.length-1;
        for(;i >= 0; i--) {
            if(rounds[lottery_no].tickets[i].owner == msg.sender) {
                return (rounds[lottery_no].tickets[i].ticketNo,1);
            }
        }
        return (0,0);
    }

    function getIthOwnedTicketNo(uint i,uint lottery_no) public view returns(uint,uint8 status) {
        lottery_no--;
        uint j = 0;
        for(;j < rounds[lottery_no].tickets.length; j++) {
            if(rounds[lottery_no].tickets[j].owner == msg.sender) {
                if(i == 1) {
                    return (rounds[lottery_no].tickets[j].ticketNo,1);
                }
                i--;
            }
        }
        return (0,0);
    }

    // it should be run end of the reveal phase
    function determineWinningNumber(uint lottery_no) private {
        lottery_no--;
        Round memory round = rounds[lottery_no];
        uint i = 0;
        uint n = 0;
        for(; i<round.tickets.length; i++) {
            if(round.tickets[i].revealed == true && round.tickets[i].refunded == false) {
                n ^= round.tickets[i].rnd_number;
            }
        }
        uint winnerCount = log(amountCollectedOfLottery[lottery_no])+1;
        i = 1;
        for(;i<winnerCount+1; i++) {
            n = getKeccak256Hash(n);

            uint prize = (amountCollectedOfLottery[lottery_no]/(2*i)) + (amountCollectedOfLottery[lottery_no]/(2*(i-1))) % 2;
            uint winnerTicketIndex = n%rounds[lottery_no].tickets.length;
            rounds[lottery_no].tickets[winnerTicketIndex].prize += prize;
        }
    }

    function log(uint m) private pure returns(uint ceiling){
        uint exponential = 1;
        uint count = 0;
        while(true) {
            if(m < exponential) {
                return count;
            }
            count += 1;
            exponential *= 2;
        }
    }

    function getKeccak256Hash(uint256 num) private pure returns (uint hash) {
        return uint(keccak256(abi.encodePacked(num)));
    }

    function checkIfTicketWon(uint ticket_no) public newRound returns (uint amount) {
        (uint amnt, uint lottery_no) = checkIfTicketWonExtended(ticket_no);
        return amnt;
    }

    function checkIfTicketWonExtended(uint ticket_no) private view returns(uint amount, uint lottery_no) {
        uint i = 0;
        for(;i<currentLotteryId; i++) {
            Round memory round = rounds[i];
            uint index = ticket_no - round.firstTicketNo;
            if(index < round.tickets.length && round.tickets[index].ticketNo == ticket_no && round.tickets[index].revealed) {
                return (round.tickets[index].prize,i);
            }
        }
        return (0,0);
    }

    function collectTicketPrize(uint ticket_no) public newRound {
        (uint amnt, uint lottery_no) = checkIfTicketWonExtended(ticket_no);
        if(amnt == 0 || rounds[lottery_no].tickets[ticket_no-rounds[lottery_no].firstTicketNo].collected) {
            revert();
        }
        if(!_turkishLira.transfer(msg.sender,amnt)) {
            revert();
        }
        rounds[lottery_no].tickets[ticket_no-rounds[lottery_no].firstTicketNo].collected = true;
        
    }

    function getIthWinningTicket(uint i, uint lottery_no) public view returns (uint ticket_no, uint amount) {
        lottery_no--;
        for(uint j = 0; j < rounds[lottery_no].tickets.length; j++) {
            if(i == 1) {
                return (rounds[lottery_no].tickets[j].ticketNo,rounds[lottery_no].tickets[j].prize);
            }
            i--;
        }
        return (0,0);
    }

    function getLotteryNo(uint unixtimeinweek) public view returns (uint lottery_no) {
        return (unixtimeinweek - initTime) / (purchasePeriod + revealPeriod) + 1;
    }
}