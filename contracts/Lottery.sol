// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TurkishLira.sol";
contract Lottery is ERC721 {

    struct Ticket {
        uint256 ticketNo;
        address owner;
        bytes32 hashRndNumber;
        uint rndNumber;
        uint256 lotteryId;
        bool revealed;
        bool refunded;
        uint prize;
        bool collected;
    }

    struct Round {
        uint xored;
        uint firstTicketNo;
        Ticket[] tickets;
    }

    mapping(address => uint256) public balances;
    TurkishLira _turkishLira;
    uint256 lastTicketId;
    mapping(uint => uint) public amountCollectedOfLottery;
    mapping(uint => Round) public rounds;
    uint initTime;
    uint purchasePeriod = 0.75 minutes;
    uint revealPeriod = 0.25 minutes;

    constructor(TurkishLira turkishLira) ERC721("Lottery","Ltry") {
        _turkishLira = turkishLira;
        initTime = block.timestamp;
        lastTicketId = 1;
        rounds[0].firstTicketNo = lastTicketId;
    }

    modifier revealPhase {
        ( ,uint purchaseDeadline, uint revealDeadline) = getCurrentRoundNoAndDeadlines(); 
        require(block.timestamp > purchaseDeadline && block.timestamp < revealDeadline);
        _;
    }

    modifier balance {
      require(balances[msg.sender] < 10);
      _;
    }

    modifier purchasePhase {
        ( ,uint purchaseDeadline, uint revealDeadline) = getCurrentRoundNoAndDeadlines();
        require(block.timestamp < purchaseDeadline);
        _;
    }

    function depositTL(uint amnt) public {
        if(_turkishLira.transferFrom(msg.sender,address(this),amnt)) {
            balances[msg.sender] += amnt;
        }
    }

    function withdrawTL(uint amnt) public {
        if(balances[msg.sender]>amnt){
            _turkishLira.approve(address(this), amnt);
            _turkishLira.transferFrom(address(this),msg.sender,amnt);
            balances[msg.sender] -= amnt;
        }
    }

    function buyTicket(bytes32 hash_rnd_number) public purchasePhase {
        (uint currentRoundNo, , ) = getCurrentRoundNoAndDeadlines();
        Ticket memory newTicket = Ticket(lastTicketId,msg.sender,hash_rnd_number,0,currentRoundNo,false,false,0,false);
        rounds[currentRoundNo].tickets.push(newTicket);
        _safeMint(msg.sender, lastTicketId);
        lastTicketId += 1;
        balances[msg.sender] -= 10;
        amountCollectedOfLottery[currentRoundNo] += 10;
    }

    function collectTicketRefund(uint ticket_no) public purchasePhase {
        (uint currentRoundNo, , ) = getCurrentRoundNoAndDeadlines();
        _burn(ticket_no);
        balances[msg.sender] += 5;
        uint firstTicketNo = rounds[currentRoundNo].firstTicketNo;
        rounds[currentRoundNo].tickets[ticket_no-firstTicketNo].refunded = true;
        amountCollectedOfLottery[currentRoundNo] -= 10; // refund 5 but keep 5 for the contract?
    }

    function revealRndNumber(uint ticketno, uint rnd_number) public revealPhase{
        (uint currentRoundNo, , ) = getCurrentRoundNoAndDeadlines();
        if(ownerOf(ticketno) != msg.sender) {
            revert();
        }
        bytes32 keccak=keccak256(abi.encodePacked(msg.sender,rnd_number));
        uint firstTicketNo = rounds[currentRoundNo].firstTicketNo;
        if(rounds[currentRoundNo].tickets[ticketno-firstTicketNo].hashRndNumber != keccak) {
            revert();
        }
        rounds[currentRoundNo].xored ^= rnd_number;
        rounds[currentRoundNo].tickets[ticketno-firstTicketNo].rndNumber = rnd_number;
        rounds[currentRoundNo].tickets[ticketno-firstTicketNo].revealed = true;
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

    function checkIfTicketWon(uint ticket_no) public view returns (uint amount) {
        (uint amnt,) = checkIfTicketWonExtended(ticket_no);
        return amnt;
    }

    function checkIfTicketWonExtended(uint ticket_no) private view returns(uint amount, uint lottery_no) {
        uint i = 0;
        (uint currentRoundNo, , ) = getCurrentRoundNoAndDeadlines();
        for(; i < currentRoundNo; i++) { 
            Round memory round = rounds[i];
            uint index = ticket_no - round.firstTicketNo;
            if(index < round.tickets.length && round.tickets[index].ticketNo == ticket_no && round.tickets[index].revealed) {
                uint winnerCount = log(amountCollectedOfLottery[i])+1;
                uint n = round.xored;
                uint prize = 0;
                for(uint j=1; j<winnerCount+1; j++) {
                    n = getKeccak256Hash(n);
                    if(n%round.tickets.length == index) {
                        prize += (amountCollectedOfLottery[i]/(2**j)) + (amountCollectedOfLottery[i]/(2**(j-1))) % 2;
                    }
                }
                return (prize,i);
            }
        }
        return (0,0);
    }

    function collectTicketPrize(uint ticket_no) public {
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
        uint n = rounds[lottery_no].xored;
        uint winnerCount = log(amountCollectedOfLottery[lottery_no])+1;
        if(i > winnerCount) {
            revert();
        }
        for(; i>0; i--) {
            n = getKeccak256Hash(n);
        }
        uint index = n%rounds[lottery_no].tickets.length;
        uint ticketNo = rounds[lottery_no].tickets[index].ticketNo;
        (uint amnt, ) = checkIfTicketWonExtended(ticketNo);
        return (ticketNo,amnt);
    }

    function getCurrentRoundNoAndDeadlines() private view returns(uint currentRound, uint purchaseDL, uint revealDL) {
        uint currentRoundNo = (block.timestamp - initTime) / (purchasePeriod + revealPeriod);
        uint purchaseDeadline = initTime + (currentRoundNo) * (purchasePeriod + revealPeriod) + purchasePeriod;
        uint revealDeadline = purchaseDeadline + revealPeriod;
        return(currentRoundNo, purchaseDeadline, revealDeadline);
    }

    function getLotteryNo(uint unixtimeinweek) public view returns (uint lottery_no) {
        return (unixtimeinweek - initTime) / (purchasePeriod + revealPeriod) + 1;
    }

    function getXored() public view returns(uint){
        return rounds[0].xored;
    }
}