// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


//import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
//import "./Token.sol";
import "./UtilityFunctions.sol";

contract MudMiningEscrow {

     uint constant secPerMonth = 2592000;
     struct Transaction {
        uint startTime;
        uint endTime;
        uint256 amount;
     }
     
     struct Cursor {
         uint256 start;
         uint256 end;
     }

    mapping (address => mapping (uint256 => Transaction)) private _logbook;
    mapping (address => Cursor) private _cursors;
        
    MetaUserDAOToken token;
    address immutable admin;
    bool private _depositMappingFinished;

    event depositMappingEvt(address, uint256);
    event depositEvt(uint256 depositId);
    event breakContractEvt(uint256 burnAmount, uint256 amountLeft);
    event withdrawEvt(uint256 freeAmount, uint256 lockedAmount);
    event depositmappingfinalized(string mappingFinalized);
    
    constructor()  {
        admin = address(msg.sender);
        token = UtilityFunctions.getMudToken();
    }
    
    //start a mining order
    function deposit(uint256 amount, uint8 duration) external returns (uint256) {
        require(msg.sender != admin, "Not admin !");
        require(_depositMappingFinished, "Wait until deposit mapping finished !");
        require(duration == 3 || duration == 6 || duration == 12, "Only 3,6,12 allowed !");
        require(amount > 0, "amount should > 0 !");
        
        if (_cursors[msg.sender].start == 0) {
            _cursors[msg.sender].start = 1;
            _cursors[msg.sender].end = 1;
        } else {
            _cursors[msg.sender].end = ++_cursors[msg.sender].end;
        }
        
        uint256 end = _cursors[msg.sender].end;
        
        //_logbook[msg.sender][end].duration = duration;
        _logbook[msg.sender][end].startTime = block.timestamp;
        _logbook[msg.sender][end].endTime = block.timestamp + secPerMonth * duration;
        _logbook[msg.sender][end].amount = amount;
        
        require(token.transferFrom(msg.sender, address(this), amount), "Token transferFrom failed !");
        
        //emit deposit id
        emit depositEvt(end);
        return end;
    }

    //mapping the existing deposit orders from ethereum main chain
    function depositMapping(address depositAddress, uint256[] calldata orderIdArray, uint[] calldata starttimeArray, uint[] calldata endtimeArray, uint256[] calldata amountArray) external returns (address, uint256) {
        require(msg.sender == admin, "Only admin allowed!");
        require(!_depositMappingFinished, "Deposit mapping finished already!");
        require(depositAddress != admin && depositAddress != address(0), "Invalid address");
        require(orderIdArray.length == starttimeArray.length && starttimeArray.length == endtimeArray.length && starttimeArray.length == amountArray.length, "Array length not match");  
        
        uint256 totalAmount;

        for (uint i = 0; i < starttimeArray.length; i++) {      
            require(orderIdArray[i] > 0, "Invalid orderId!");      
            require(amountArray[i] > 0, "amount should > 0");
            require(starttimeArray[i] < endtimeArray[i], "start time should < end time!");
            
            //initialize the start and end to the first order
            if (_cursors[depositAddress].start == 0) {
                 _cursors[depositAddress].start = orderIdArray[i];
                 _cursors[depositAddress].end = orderIdArray[i];
            } else {
                if (orderIdArray[i] < _cursors[depositAddress].start) {
                    _cursors[depositAddress].start = orderIdArray[i];
                }
                if (orderIdArray[i] > _cursors[depositAddress].end) {
                    _cursors[depositAddress].end = orderIdArray[i];
                }
            }

            _logbook[depositAddress][orderIdArray[i]].startTime = starttimeArray[i];
            _logbook[depositAddress][orderIdArray[i]].endTime = endtimeArray[i];
            _logbook[depositAddress][orderIdArray[i]].amount = amountArray[i];                    

            totalAmount += amountArray[i];
        }                
                
        require(token.transferFrom(msg.sender, address(this), totalAmount), "Token transferFrom failed !");
        
        //emit deposit id
        emit depositMappingEvt(depositAddress, totalAmount);
        return (depositAddress, totalAmount);
    }
    
    //break a mining order
    function breakContract(uint256 contractId) external returns(uint256, uint256) {
        require(_depositMappingFinished, "Wait until deposit mapping finished !");
        require(msg.sender != admin, "Not admin !");
        require(contractId > 0, "contractId should > 0 !");
        require(contractId >= _cursors[msg.sender].start && contractId <= _cursors[msg.sender].end, "Invalid contractId!");
        require(_logbook[msg.sender][contractId].amount > 0, "No token in contract !");
        require(block.timestamp > _logbook[msg.sender][contractId].startTime, "time should > contract startTime");
        
        if (block.timestamp > _logbook[msg.sender][contractId].endTime) {
            emit breakContractEvt(0, _logbook[msg.sender][contractId].amount);
            return (0, _logbook[msg.sender][contractId].amount); //0 burnt, all amount free for withdraw
        } else if (block.timestamp + 86400 >= _logbook[msg.sender][contractId].endTime) { //the contract will end sooner than 24 hours so no need to break earlier. burnAmount == contract amount means no break needed
            emit breakContractEvt(_logbook[msg.sender][contractId].amount, _logbook[msg.sender][contractId].amount);
            return (_logbook[msg.sender][contractId].amount, _logbook[msg.sender][contractId].amount); //all amount still waiting for mature within 24 hrs        
        } else { //if (now + 86400 < _logbook[msg.sender][contractId].endTime), burn 20% tokens immediately and end the contract after 24 hours from now before the end time
            //burn 20%
            uint256 burnAmount = _logbook[msg.sender][contractId].amount / 5;
            _logbook[msg.sender][contractId].amount = _logbook[msg.sender][contractId].amount - burnAmount;
            _logbook[msg.sender][contractId].endTime = block.timestamp + 86400; //86400
           
            token.burn(burnAmount);

            emit breakContractEvt(burnAmount, _logbook[msg.sender][contractId].amount);   
            return (burnAmount, _logbook[msg.sender][contractId].amount);  
        }
    }
    
    //check total matured order amount and inmature amount
    function checkBalance(address addressIn) external view returns (uint256, uint256) {
        require(_depositMappingFinished, "Wait until deposit mapping finished !");
        require(addressIn != address(0), "Blackhole address not allowed!");
        
        address addressToCheck = msg.sender;
        
        if (msg.sender == admin) {
            addressToCheck = addressIn;
        }
        
        require(_cursors[addressToCheck].start <= _cursors[addressToCheck].end, "Nothing in the mining logbook!");

        if (_cursors[addressToCheck].start == 0) {
            return (0, 0);
        }
        
        uint256 freeAmount = 0;
        uint256 lockedAmount = 0;
        
        for (uint256 i = _cursors[addressToCheck].start; i <= _cursors[addressToCheck].end; i++) {
            if (_logbook[addressToCheck][i].amount > 0) {
                if (block.timestamp >= _logbook[addressToCheck][i].startTime) {
                    if (block.timestamp <= _logbook[addressToCheck][i].endTime) {
                        lockedAmount = lockedAmount + _logbook[addressToCheck][i].amount;
                    } else {
                        freeAmount = freeAmount + _logbook[addressToCheck][i].amount;
                    }
                }
            }//of amount > 0
        }
        
        return (freeAmount, lockedAmount);
    }
    
    //withdraw matured order amount
    function Withdraw() external returns (uint256, uint256) {
        require(_depositMappingFinished, "Wait until deposit mapping finished !");
        require(msg.sender != admin, "Admin not allowed !");
        require(_cursors[msg.sender].start > 0, "No mining contracts.");
        require(_cursors[msg.sender].start <= _cursors[msg.sender].end, "Invalid mining start,end pointers!");
        
        uint256 freeAmount = 0;
        uint256 lockedAmount = 0;
        bool foundNextStart = false;
        
        for (uint256 i = _cursors[msg.sender].start; i <= _cursors[msg.sender].end; i++) {
            if (_logbook[msg.sender][i].amount > 0) {
                if (block.timestamp >= _logbook[msg.sender][i].startTime) {
                    if (block.timestamp <= _logbook[msg.sender][i].endTime) {
                        lockedAmount = lockedAmount + _logbook[msg.sender][i].amount;
                        
                        if (!foundNextStart) {
                            foundNextStart = true;
                            _cursors[msg.sender].start = i;
                        }
                    } else {
                        freeAmount = freeAmount + _logbook[msg.sender][i].amount;
                        _logbook[msg.sender][i].amount = 0;
                    }
                }
            }//of amount > 0`
        }// of for
        
        if (!foundNextStart) {
            _cursors[msg.sender].start = _cursors[msg.sender].end;
        }
        
        if (freeAmount > 0) {
            require(token.transfer(msg.sender, freeAmount), "Token transfer failed !");           
        }
        
        emit withdrawEvt(freeAmount, lockedAmount);
        return (freeAmount, lockedAmount);
    }

    //get order information base on orderId
    function getDepositOrderInfo(address addressToCheck, uint256 orderId) external view returns (uint256, uint256, uint256) {
        require(_depositMappingFinished, "Wait until deposit mapping finished !");
        require(msg.sender == admin, "Not admin !");
        require(addressToCheck != address(0), "Blackhole address not allowed!");               
        require(_cursors[addressToCheck].start <= _cursors[addressToCheck].end, "Nothing in the mining logbook!");
        require(orderId >= _cursors[addressToCheck].start && orderId <= _cursors[addressToCheck].end, "Invalid orderId");

        if (_cursors[addressToCheck].start == 0) {
            return (0, 0, 0);
        }       
        
        return (_logbook[addressToCheck][orderId].startTime, _logbook[addressToCheck][orderId].endTime, _logbook[addressToCheck][orderId].amount);
   }
   
    //mark the depositMapping finished flag, stop depositMapping any more and return the _depositMappingTotal.    
    function depositMappingFinalised() external {
        require(msg.sender == admin, "Not contractor owner!");
        require(!_depositMappingFinished, "Deposit mapping finished already!");
        
        _depositMappingFinished = true;
        emit depositmappingfinalized("Deposit mapping finalized !");       
    } 
}

