// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./TurkishLira.sol";
library Math {
   function log2(uint x) public returns (uint y){
   assembly {
        let arg := x
        x := sub(x,1)
        x := or(x, div(x, 0x02))
        x := or(x, div(x, 0x04))
        x := or(x, div(x, 0x10))
        x := or(x, div(x, 0x100))
        x := or(x, div(x, 0x10000))
        x := or(x, div(x, 0x100000000))
        x := or(x, div(x, 0x10000000000000000))
        x := or(x, div(x, 0x100000000000000000000000000000000))
        x := add(x, 1)
        let m := mload(0x40)
        mstore(m,           0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd)
        mstore(add(m,0x20), 0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe)
        mstore(add(m,0x40), 0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616)
        mstore(add(m,0x60), 0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff)
        mstore(add(m,0x80), 0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e)
        mstore(add(m,0xa0), 0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707)
        mstore(add(m,0xc0), 0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606)
        mstore(add(m,0xe0), 0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100)
        mstore(0x40, add(m, 0x100))
        let magic := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
        let shift := 0x100000000000000000000000000000000000000000000000000000000000000
        let a := div(mul(x, magic), shift)
        y := div(mload(add(m,sub(255,a))), shift)
        y := add(y, mul(256, gt(arg, 0x8000000000000000000000000000000000000000000000000000000000000000)))
    }  
}
}
contract Lottery is ERC721 {

    struct Ticket {
        uint256 id;
        address owner;
        bytes32 hash_rnd_number;
        uint rnd_number;
        uint256 lotteryId;
        bool revealed;
        bool refunded;
    }

    struct Round {
        uint lotteryNo;
        uint firstTicketNo;
        Ticket[] tickets;
        uint[] winners;
    }

    mapping(address => uint256) public balances;
    //mapping(address => mapping(uint => Ticket)) public tickets;
    mapping(uint=>uint256[]) public winnerIndices;
    TurkishLira _turkishLira;
    uint256 lastTicketId;
    uint256 currentLotteryId;
    uint purchaseDeadline;
    uint revealDeadline;
    bool isRevealPhase=false;
    //mapping(uint => Ticket[]) public ticketsOfLottery;
    mapping(uint => uint[]) public winnerTicketsNoOfLottery;
    mapping(uint => uint) public amountCollectedOfLottery;
    mapping(uint => Round) public rounds;

    constructor(TurkishLira turkishLira) ERC721("Lottery","Ltry") {
        _turkishLira = turkishLira;
        lastTicketId = 0;
        currentLotteryId = 0;
        Round memory firstRound;
        firstRound.firstTicketNo = lastTicketId;
        firstRound.lotteryNo = currentLotteryId;
        purchaseDeadline = block.timestamp + 4 days;
        revealDeadline = block.timestamp + 7 days;
        amountCollectedOfLottery[currentLotteryId] = 0;
    }

    modifier revealPhase {
      require(block.timestamp > purchaseDeadline && block.timestamp < revealDeadline);
      _;
    }

    modifier balance {
      require(balances[msg.sender] < 10);
      _;
    }

    modifier submissionPhase {
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

    function buyTicket(bytes32 hash_rnd_number) public  {
        
        
        lastTicketId += 1;
        Ticket memory newTicket = Ticket(lastTicketId,msg.sender,hash_rnd_number,0,currentLotteryId,false,false);
        //tickets[msg.sender][newTicket.id] = newTicket;
        //ticketsOfLottery[currentLotteryId].push(newTicket);
        rounds[currentLotteryId].tickets.push(newTicket);
        _safeMint(msg.sender, lastTicketId);
        
        balances[msg.sender] -= 10;
        amountCollectedOfLottery[currentLotteryId] += 10;
    }

    function collectTicketRefund(uint ticket_no) public submissionPhase {
        _burn(ticket_no);
        balances[msg.sender] += 5;
        uint firstTicketNo = rounds[currentLotteryId].firstTicketNo;
        rounds[currentLotteryId].tickets[ticket_no-firstTicketNo].refunded = true;
        amountCollectedOfLottery[currentLotteryId] -= 10; // refund 5 but keep 5 for the contract?
    }

    function revealRndNumber(uint ticketno, uint rnd_number) public {
        if(ownerOf(ticketno) != msg.sender) {
            revert();
        }
        bytes32 keccak=keccak256(abi.encodePacked(rnd_number));
        uint firstTicketNo = rounds[currentLotteryId].firstTicketNo;
        if(rounds[currentLotteryId].tickets[ticketno-firstTicketNo].hash_rnd_number != keccak) {
            revert();
        }
        rounds[currentLotteryId].tickets[ticketno-firstTicketNo].rnd_number = rnd_number;
        rounds[currentLotteryId].tickets[ticketno-firstTicketNo].revealed = true;
    }

    function getLastOwnedTicketNo(uint lottery_no) public view returns(uint,uint8 status) {
        uint i = rounds[lottery_no].tickets.length-1;
        for(;i >= 0; i--) {
            if(rounds[lottery_no].tickets[i].owner == msg.sender) {
                return (rounds[lottery_no].tickets[i].id,1);
            }
        }
        return (0,0);
    }

    function getIthOwnedTicketNo(uint i,uint lottery_no) public view returns(uint,uint8 status) {
        uint j = 0;
        for(;j < rounds[lottery_no].tickets.length; j++) {
            if(rounds[lottery_no].tickets[j].owner == msg.sender) {
                if(i == 0) {
                    return (rounds[lottery_no].tickets[j].id,1);
                }
                i--;
            }
        }
        return (0,0);
    }

    // it should be run end of the reveal phase
    function determineWinningNumber(uint lottery_no) public {
        uint i = 0;
        uint length = rounds[lottery_no].tickets.length;
        while(i < length && !rounds[lottery_no].tickets[i].revealed){
            i++;
        }
        bytes32 winningNumber = bytes32(rounds[lottery_no].tickets[i].rnd_number);
        for(; i < length; i++) {
            winningNumber ^= bytes32(rounds[lottery_no].tickets[i].rnd_number);

        }
        winnerIndices[lottery_no].push(uint(winningNumber)%(i+1));
        winnerTicketsNoOfLottery[lottery_no].push(rounds[lottery_no].tickets[uint(winningNumber)%(i+1)].id);

        uint numOfPrizes=Math.log2(amountCollectedOfLottery[lottery_no]);
        for(uint j=1; j<numOfPrizes;j++){
            winningNumber=keccak256(abi.encodePacked(winningNumber));
            winnerIndices[lottery_no].push((uint256(winningNumber)%(i+1)));
            winnerTicketsNoOfLottery[lottery_no].push(rounds[lottery_no].tickets[uint(winningNumber)%(i+1)].id);
        }
        
    }

    function getKeccak256Hash(uint256 num) public returns (bytes32) {
        return keccak256(abi.encodePacked(num));
    }
    /*function getIthPrize(uint i) public returns (uint){
        return amountCollectedOfLottery[0]/2*(i-1) + amountCollectedOfLottery[0]/2*(i-1)%2;
    }*/

    function checkIfTicketWon(uint ticket_no) public view returns (uint amount){
        for(uint i=1;i<winnerTicketsNoOfLottery[0].length;i++){
            if(winnerTicketsNoOfLottery[0][i]==ticket_no){
                return amountCollectedOfLottery[0]/2*(i-1) + amountCollectedOfLottery[0]/2*(i-1)%2;
            }
        }
    }



}