// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


//import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
//import "./Token.sol";
import "./UtilityFunctions.sol";


contract MudABRoundReleaseBank {
     
    address immutable admin; //contract creator
    uint256 constant ABRoundLimit = 3e14;//300000000000000;//rouna A and B total limit 250000000 MUD
    uint256 constant dailyRate = 92590; //0.0009259 daily release rate 0.09259%
    uint constant secPerDay = 86400;
    uint256 private _depositMappingTotal;
    bool private _depositMappingFinished;
    MetaUserDAOToken token;

    event depositMappingEvt(uint256 releaseStartTime, uint256 totalLocked);
    event releasetoken(uint256 freeAmount, uint256 balance);
    event depositmappingfinalized(string mappingFinalized);
                                               
    struct Transaction {
        bool locked;
        uint lastTime;
        uint256 balance;
        uint256 dailyReleaseAmount;
    }
    
    mapping(address => Transaction) bank;   
   
    constructor() {
        admin = msg.sender;//set contract owner, which is the MetaUserDAO team administrator account with multisig transaction setup.
        token = UtilityFunctions.getMudToken();//MudTestToken(mudtTokenContractAddr);
    }
    
    
    /*only the contractor creator could deposit mapping to investor
    * map the MUD AB round from eth mainnet contract 
    * parameters:
    *     addressArray: Angel round investor addresses 
    *     icoBalanceArray: array of amount of MUD coin received from AB round
    *     balanceArray: array of amount of MUD coin mapped from eth mainnet contract
    *     lasttimeArray: lasttime mapped from eth mainnet contract
    * return:  (block time, total coins deposited in the contract)   
    */ 
    function depositMapping(address[] calldata addressArray, uint256[] calldata icoBalanceArray, uint256[] calldata balanceArray, uint[] calldata lasttimeArray) external returns (uint256, uint256){
        require(msg.sender == admin, "Only admin can deposit.");
        require(!_depositMappingFinished, "Deposit Mapping finished!");
        require(addressArray.length == balanceArray.length && icoBalanceArray.length == balanceArray.length && balanceArray.length == lasttimeArray.length, "Array length not match");        

        //iterate through the array
        uint256 totalDepositToBeTransferred;
        
        for (uint i = 0; i < addressArray.length; i++) {
            require(balanceArray[i] > 0, "Mapped balance should > 0");        
            require(icoBalanceArray[i] >= balanceArray[i], "Incorrect balance!");    
            require(balanceArray[i] +  _depositMappingTotal + totalDepositToBeTransferred <= ABRoundLimit, "_depositMappingTotal out of the ico limit!");              
            require(lasttimeArray[i] >= 1671200891, "last releaseToken() timestamp < eth ico deposit time! ");//should > ico deposit time on eth main chain
            

            address investorAddress = addressArray[i];
            require(investorAddress != admin && investorAddress != address(0), "invalid address");
            require(!bank[investorAddress].locked, "already locked.");

            bank[investorAddress].lastTime = lasttimeArray[i];
            bank[investorAddress].balance = balanceArray[i];
            bank[investorAddress].dailyReleaseAmount = icoBalanceArray[i] * dailyRate / 1e8; //amount * dailyRate / 100000000;
            bank[investorAddress].locked = true;
            totalDepositToBeTransferred = totalDepositToBeTransferred + balanceArray[i];
        }
        _depositMappingTotal = _depositMappingTotal + totalDepositToBeTransferred;//to save gas
        require(token.transferFrom(msg.sender, address(this), totalDepositToBeTransferred), "transferFrom failed!"); //check the return value, it should be true
        
        emit depositMappingEvt(block.timestamp, _depositMappingTotal);
        return (block.timestamp, _depositMappingTotal);
    }
    
    /* investor call this function from the dapp to check the amount of their coins in the AB round locked contract
     * parameters: adressIn: for admin account it can be any investor address, for investor the adressIn is not used
     * returns: 
     *         (free MUD coins ready for withdraw, total MUD coins of the investor in the contract)
     */
    function checkBalance(address addressIn) external view returns  (uint256 , uint256 ) {
        require(addressIn != address(0), "Blackhole address not allowed!");
        
        address addressToCheck = msg.sender;
        
        if (msg.sender == admin) {
            addressToCheck = addressIn;
        }

        //require(block.timestamp > bank[addressToCheck].lastTime, "now time < lastTime");
        
        if (bank[addressToCheck].balance <= 0) {
            return (0, 0);
        }
        
        //The freeAmount should be matured based on exact times of the 24 hours.
        //Thus we should calculate the matured days. The leftover time which is not a whole 24 hours
        //should wait for the next mature time spot.
        uint256 maturedDays = (block.timestamp - bank[addressToCheck].lastTime) / secPerDay;
        uint256 freeAmount = bank[addressToCheck].dailyReleaseAmount * maturedDays;//even 0 matured days will work
        
        if (freeAmount > bank[addressToCheck].balance) {
            freeAmount = bank[addressToCheck].balance;
        }

        return (freeAmount, bank[addressToCheck].balance);
    }
    
     /* release the free tokens to the investor's wallet address
     * parameters: NONE 
     * returns:  (released amount, amount still locked in the contract)
     */
    function releaseToken() external returns  (uint256, uint256) {
        require(msg.sender != admin, "msg.send == admin");
        require(bank[msg.sender].balance > 0, "balance <= 0");
        require(block.timestamp > bank[msg.sender].lastTime + secPerDay, "now < lastTime + secPerDay");
        
        //The freeAmount should be matured based on exact times of the 24 hours.
        //Thus we should calculate the matured days. The leftover time which is not a whole 24 hours
        //should wait for the next mature time spot.
        uint256 maturedDays = (block.timestamp - bank[msg.sender].lastTime) / secPerDay;
        uint256 freeAmount = bank[msg.sender].dailyReleaseAmount * maturedDays;
        
        if (freeAmount > bank[msg.sender].balance) {
            freeAmount = bank[msg.sender].balance;
        }
        
        bank[msg.sender].lastTime = bank[msg.sender].lastTime + maturedDays * secPerDay;//should set to the exact spot based on 24 hours
        bank[msg.sender].balance = bank[msg.sender].balance - freeAmount;
        require(token.transfer(msg.sender, freeAmount), "token transfer failed !");

        emit releasetoken(freeAmount, bank[msg.sender].balance);        
        return (freeAmount, bank[msg.sender].balance);
    }

    //mark the depositMapping finished flag, stop depositMapping any more and return the _depositMappingTotal.    
    function depositMappingFinalised() external returns (uint256) {
        require(msg.sender == admin, "Not contractor owner!");
        require(!_depositMappingFinished, "Deposit mapping finished already!");
        
        _depositMappingFinished = true;
        emit depositmappingfinalized("Deposit mapping finalized !");
        return _depositMappingTotal;
    }
    
    //get deposit information for mainnet mapping purpose
    function getDepositInfo(address addressToCheck) external view returns  (uint256 , uint256, uint256, bool ){
        require(msg.sender == admin, "Only admin can call.");
        require(addressToCheck != address(0), "addressToCheck should not = 0.");
        require(addressToCheck != admin, "addressToCheck should not be admin address !");

        return (bank[addressToCheck].lastTime, 
               bank[addressToCheck].balance,
               bank[addressToCheck].dailyReleaseAmount, 
               bank[addressToCheck].locked);        
    } 

}
