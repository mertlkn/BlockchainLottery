// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TurkishLira.sol";

contract Lottery is ERC721 {

    struct Ticket {
        uint256 id;
        address owner;
        bytes32 hash;
        bytes32 ticketNo;
        uint256 lotteryId;
    }

    mapping(address => uint256) public balances;
    mapping(address => Ticket[]) public tickets;
    TurkishLira _turkishLira;
    uint256 lastTicketId;
    uint256 currentLotteryId;

    constructor(TurkishLira turkishLira) ERC721("Lottery","Ltry") {
        _turkishLira = turkishLira;
        lastTicketId = 0;
        currentLotteryId = 1;
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
        lastTicketId += 1;
        Ticket memory newTicket = Ticket(lastTicketId,msg.sender,hash_rnd_number,0,currentLotteryId);
        tickets[msg.sender].push(newTicket);
        _safeMint(msg.sender, lastTicketId);
        balances[msg.sender] -= 10;
    }

}