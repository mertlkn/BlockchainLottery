// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TurkishLira.sol";

contract Lottery is ERC721 {

    struct Ticket {
        uint256 id;
        address owner;
        bytes32 hash_rnd_number;
        uint rnd_number;
        uint256 lotteryId;
        bool revealed;
    }

    mapping(address => uint256) public balances;
    mapping(address => mapping(uint => Ticket)) public tickets;
    TurkishLira _turkishLira;
    uint256 lastTicketId;
    uint256 currentLotteryId;
    uint purchaseDeadline;
    uint revealDeadline;
    mapping(uint => Ticket[]) public ticketsOfLottery;
    mapping(uint => uint) public amountCollectedOfLottery;

    constructor(TurkishLira turkishLira) ERC721("Lottery","Ltry") {
        _turkishLira = turkishLira;
        lastTicketId = 0;
        currentLotteryId = 0;
        purchaseDeadline = block.timestamp + 4 days;
        revealDeadline = block.timestamp + 7 days;
        amountCollectedOfLottery[currentLotteryId] = 0;
    }

    function depositTL(uint amnt) public {
        if(_turkishLira.transferFrom(msg.sender,address(this),amnt)) {
            balances[msg.sender] += amnt;
        }
    }

    function withdrawTL(uint amnt) public {
        if(_turkishLira.transferFrom(address(this),msg.sender,amnt)) {
            balances[msg.sender] -= amnt;
        }
    }

    function buyTicket(bytes32 hash_rnd_number) public {
        if(balances[msg.sender] < 10) {
            revert();
        }
        if(block.timestamp > purchaseDeadline && block.timestamp < revealDeadline) {
            revert();
        }
        lastTicketId += 1;
        Ticket memory newTicket = Ticket(lastTicketId,msg.sender,hash_rnd_number,0,currentLotteryId,false);
        tickets[msg.sender][newTicket.id] = newTicket;
        ticketsOfLottery[currentLotteryId].push(newTicket);
        _safeMint(msg.sender, lastTicketId);
        balances[msg.sender] -= 10;
        amountCollectedOfLottery[currentLotteryId] += 10;
    }

    function collectTicketRefund(uint ticket_no) public {
        if(block.timestamp > revealDeadline || block.timestamp < purchaseDeadline) {
            revert();
        }
        _burn(ticket_no);
        balances[msg.sender] += 5;
        amountCollectedOfLottery[currentLotteryId] -= 10; // refund 5 but keep 5 for the contract?
    }

    function revealRndNumber(uint ticketno, uint rnd_number) public {
        if(block.timestamp > revealDeadline || block.timestamp < purchaseDeadline) {
            revert();
        }
        if(ownerOf(ticketno) != msg.sender) {
            revert();
        }
        if(tickets[msg.sender][ticketno].hash_rnd_number != keccak256(abi.encodePacked(rnd_number))) {
            revert();
        }
        tickets[msg.sender][ticketno].rnd_number = rnd_number;
        tickets[msg.sender][ticketno].revealed = true;
    }

    function getLastOwnedTicketNo(uint lottery_no) public view returns(uint,uint8 status) {
        uint i = ticketsOfLottery[lottery_no].length-1;
        for(;i >= 0; i--) {
            if(ticketsOfLottery[lottery_no][i].owner == msg.sender) {
                return (ticketsOfLottery[lottery_no][i].id,1);
            }
        }
        return (0,0);
    }

    function getIthOwnedTicketNo(uint i,uint lottery_no) public view returns(uint,uint8 status) {
        uint j = 0;
        for(;j < ticketsOfLottery[lottery_no].length; j++) {
            if(ticketsOfLottery[lottery_no][i].owner == msg.sender) {
                i--;
                if(i == 0) {
                    return (ticketsOfLottery[lottery_no][j].id,1);
                }
            }
        }
        return (0,0);
    }

}