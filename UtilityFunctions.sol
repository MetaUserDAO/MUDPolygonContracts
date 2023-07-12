// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Token_flattened.sol";

library UtilityFunctions {

    address constant mudtTokenContractAddr = address(0xf6EaC236757e82D6772E8bD02D36a0c791d78C51);//contrct address of the MUD token, should deploy the token contract first and set the contract address here
    
    function getMudToken() internal pure returns(MetaUserDAOToken){
        MetaUserDAOToken token = MetaUserDAOToken(mudtTokenContractAddr);
        
        return token;
    }
}