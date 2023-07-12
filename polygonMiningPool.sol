// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


//import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
//import "./Token.sol";
import "./UtilityFunctions.sol";


contract MudMiningPool {
    
    //mining DAPP address should be set at the contract deployment time to the correct one
    //this is the address that MUD Mining DAPP used to interact with the daily settlement function
    address constant miningDappAddress = address(0x2de5A24f9A5Ac86F87C37ab5b0Fdd7031E1015A3);   
    uint constant secPerDay = 86400;
    uint256 constant poolInfoMappingAmountLimit =432474157085699;//4.5e14;//exact number should be retrieved from eth mainnet once the MUD token freezed for mainnet mapping

    MetaUserDAOToken token;
    address immutable admin;
    uint lastHalvingTime;
    uint lastSettlementTime;
    uint256 dailyMiningLimit;
    uint256 constant settlementPeriod = 7; //7 days
    bool poolInfoMappingDepositFinished; //default value is false
    bool poolInfoMappingFinished;
    
    uint256 _currentSettlementTimestamp;
    uint256 _currentSettlementBatchNo;
    uint256 _totalSettlementAmount;    
    uint256 private _totalFreeAmount;
    mapping (address => uint256) private _minedToken;
    
    event poolmappingdeposit(uint256 amount, uint256 balance);
    event poolinfomapping(bool done);
    event poolinfomappingfinished(bool finished);
    event settlementEvt(uint256 batchNumber, uint256 burntAmount, uint256 minedAmount, uint256 totalfreeamount);
    event withdrawevt(uint256 amount);

    constructor() {
        admin = address(msg.sender);
        token = UtilityFunctions.getMudToken();
        dailyMiningLimit = 100354078820; //100354.078820 MUD per day, within 4 years, so it should be the same as eth mainnet
        //TODO: set the lastHalvingTime, lastSettlementTime, dailyMiningLimit based on eth mainnet data
        lastHalvingTime = 1671518435; //within 4 years, so it should be the same as mining start time of eth mainnet
        lastSettlementTime = 1688452835;//need to set once the eth mainnet token was frozen
    }
    
    function poolInfoMappingDeposit(uint256 amount) external returns (uint256, uint256) {
        require(msg.sender == admin, "only admin allowed!");
        require(amount == poolInfoMappingAmountLimit, "Invalid amount !"); 
        require(!poolInfoMappingDepositFinished, "Only deposit once !");//only deposit once 
        
        poolInfoMappingDepositFinished = true;
        require(token.transferFrom(msg.sender, address(this), amount), "token transfer failed !");
        emit poolmappingdeposit(amount, token.balanceOf(address(this)));

        return (amount, token.balanceOf(address(this)));
    }

    function poolInfoMapping(address[] calldata addressArray, uint256[] calldata balanceArray) external returns (bool) {
        require(msg.sender == admin, "Only admin allowed!");
        require(!poolInfoMappingFinished, "Pool mapping finished already");
        require(addressArray.length == balanceArray.length, "Array length not match!");

        uint256 localTotalFreeAmount = _totalFreeAmount;//to save gas
        for (uint i = 0; i < addressArray.length; i++) { 
            localTotalFreeAmount = localTotalFreeAmount + balanceArray[i];
            require(addressArray[i] != admin && addressArray[i] != miningDappAddress, "admin and dapp acc not allowed!");
            require(localTotalFreeAmount <= poolInfoMappingAmountLimit, "_totalFreeAmount > limit");
            _minedToken[addressArray[i]] = balanceArray[i];
        }
        _totalFreeAmount = localTotalFreeAmount; //to save gas
        
        emit poolinfomapping(true);
        return true;
    }

    function poolInfoMappingFinalized() external returns (bool){
        require(msg.sender == admin, "Only admin allowed!");
        poolInfoMappingFinished = true;
        emit poolinfomappingfinished(true);

        return true;
    }
    
    /*
    function miningStart() external returns (uint) {
        require(msg.sender == miningDappAddress, "only dapp admin allowed!"); //only dapp address could start miningDappAddress
        require(lastHalvingTime == 0, "only start once!");
        
        lastHalvingTime = block.timestamp;
        lastSettlementTime = block.timestamp; //mining start time should be the last settlement time
        emit miningstart(lastHalvingTime);
        return lastHalvingTime;
    }*/
    
    /*
        Due to the max gas limit of one block, the settlement should seperated to several batches.
        Parameters:
                 batchNumber: start from 1, for the last batch the batchNumber must be 0
                 settlementTime: should be the same each day based on miningStart() block time
                 addressArray: addresses for settlement
                 balanceArray: amount to be settled
        Return:
                for the last batch:
                  emit settlementEvt(batchNumber, amountToBurn, _totalSettlementAmount, _totalFreeAmount); 
                for other batch:
                  emit settlementEvt(batchNumber, 0, _totalSettlementAmount, _totalFreeAmount);
                  
    */

    function miningSettlement(uint256 batchNumber, uint settlementTime, address[] calldata addressArray, uint256[] calldata balanceArray) external {
        require(msg.sender == miningDappAddress, "only dapp admin allowed!");
        //require(lastHalvingTime > 0, "mining not started !");
        require(addressArray.length == balanceArray.length, "Array length not match");
        require(settlementTime == lastSettlementTime + secPerDay * settlementPeriod, "Settlement time not match !");
        require(settlementTime <= block.timestamp, "settlementTime should <= block time!");
                
        uint256 settlementLimit = dailyMiningLimit * settlementPeriod;
        //only update the timestamp once we got the last batch
        if (batchNumber == 1) {
            require(_currentSettlementBatchNo == 0, "_currentSettlementBatchNo must be 0 at begginning !");
            require(_currentSettlementTimestamp == 0, "Could not start a new settlement before last one has accomplished !");
            _currentSettlementTimestamp = settlementTime;     
            //update the settlement batch number to the current successful one
            _currentSettlementBatchNo = 1;       
        } else if (batchNumber == 0) {      
                //batchNum 0 could be both first and last batch, thus donot check the timestamp     
                if (_currentSettlementTimestamp == 0){
                    _currentSettlementTimestamp = settlementTime;
                } else {
                    //all the following settlements batch should have the same time stamp as the first one
                    require(settlementTime == _currentSettlementTimestamp, "Settlement time not match !");
                }

                lastSettlementTime = settlementTime; 
                //reset for the next settlement
                _currentSettlementBatchNo = 0;           
                             
        } else {
            //the batch number should be 1 more than the last successful one
            require(_currentSettlementBatchNo + 1 == batchNumber, "Settlement batch number incorrect!");
            //all the following settlements batch should have the same time stamp as the first one
            require(settlementTime == _currentSettlementTimestamp, "Settlement time not match !");
            //update the settlement batch number to the current successful one
            _currentSettlementBatchNo = batchNumber;
        }

        //uint256 settlementLimit = dailyMiningLimit * settlementPeriod;
        //iterate through the array and update
        uint256 localTotalSettlementAmount = _totalSettlementAmount;//to save gas
        for (uint i = 0; i < addressArray.length; i++) {
            require(addressArray[i] != miningDappAddress && addressArray[i] != admin && addressArray[i] != address(0), "invalid address");
            require(balanceArray[i] > 0, "Settlement balance should > 0 !");
        
            localTotalSettlementAmount = localTotalSettlementAmount + balanceArray[i];
            
            require(localTotalSettlementAmount <= settlementLimit, "TotalAmount out of settlement limit!"); // > daily limit, trasaction failed.
            
            _minedToken[addressArray[i]] = _minedToken[addressArray[i]] + balanceArray[i];
        }
        _totalSettlementAmount = localTotalSettlementAmount;
        
        //batchNumber == 0 is the last batch of settlement
        if (batchNumber == 0) {
            _totalFreeAmount = _totalFreeAmount + _totalSettlementAmount;
            
            require(_totalFreeAmount <= token.balanceOf(address(this)), "Not enough tokens available !");
            
            //burn token from the pool with 2:1 ratio of totalAmount:burntAmount
            uint256 amountToBurn = _totalSettlementAmount / 2 + (settlementLimit - _totalSettlementAmount);
            uint256 leftover = token.balanceOf(address(this)) - _totalFreeAmount;

            if (leftover < amountToBurn) {
                amountToBurn = leftover; 
            }

            if (amountToBurn > 0) { //only burn if the amountToBurn > 0
                //require(token.increaseAllowance(address(this), amountToBurn), "increaseAllowance failed!");
                //token.burnFrom(address(this), amountToBurn);
                token.burn(amountToBurn);
            }

            //update mining halving dailyMiningLimit every 4 years
            //only update after the last batch of the successful settlement
            if (block.timestamp > lastHalvingTime + 126144000) {
                dailyMiningLimit = dailyMiningLimit / 2;
                lastHalvingTime = block.timestamp;
            }
            emit settlementEvt(batchNumber, amountToBurn, _totalSettlementAmount, _totalFreeAmount); 
            _totalSettlementAmount = 0; //clear for next settlement.
            _currentSettlementTimestamp = 0; //clear time stamp
                      
        } else {
            emit settlementEvt(batchNumber, 0, _totalSettlementAmount, _totalFreeAmount); 
        }               
    }

    //user can check the balance of their own account address and the contract owner can check the user's available balance for mainnet mapping purpose
    function checkBalance(address addressIn) external view returns (uint256) {
        require(addressIn != address(0), "Blackhole address not allowed!");
        require(msg.sender != miningDappAddress,"Dapp acc not allowed!");
        //require(lastHalvingTime > 0, "mining not started !");
        
        address addressToCheck = msg.sender;
        
        if (msg.sender == admin) {
            addressToCheck = addressIn;
        }

        return _minedToken[addressToCheck];
    }

    //get the important info for mainnet mapping purpose
    function getPoolInfo() external view returns (uint256, uint256, uint256, uint256){
        require(msg.sender == admin, "Only admin allowed!");

        return (lastHalvingTime, lastSettlementTime, dailyMiningLimit, _totalFreeAmount);
    }
    
    //only the customers can withdraw from wallet
    //withdraw() is banned during settlement period
    function withdraw() external returns (uint256) {
        require(msg.sender != admin && msg.sender != miningDappAddress,"admin and dapp acc not allowed!");
        //require(lastHalvingTime > 0, "mining not started !");
        require(_minedToken[msg.sender] > 0, "No token available !");
        require(_currentSettlementTimestamp == 0, "Withdraw banned in settlement period!");
        
        uint256 amount = _minedToken[msg.sender];
        _minedToken[msg.sender] = 0; 
        _totalFreeAmount = _totalFreeAmount - amount;
        require(token.transfer(msg.sender, amount), "Token transfer failed !");
        
        emit withdrawevt(amount);
        return amount;
    }
}