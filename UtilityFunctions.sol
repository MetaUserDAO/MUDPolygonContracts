// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Token_flattened.sol";

library UtilityFunctions {

    address constant mudtTokenContractAddr = address(0x90a34C6ce471382c8d0296E84264d0aA85aac68a);//contrct address of the MUD token, should deploy the token contract first and set the contract address here
    
    function getMudToken() internal pure returns(MetaUserDAOToken){
        MetaUserDAOToken token = MetaUserDAOToken(mudtTokenContractAddr);
        
        return token;
    }
}