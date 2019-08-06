/*
 * Copyright 2019, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract ArbBalanceTracker is Ownable, ERC20 {

    using SafeMath for uint256;

    struct NFTWallet {
        address contractAddress;
        mapping(uint256 => uint256) tokenIndex;
        uint256[] tokenList;
    }

    struct TokenWallet {
        address contractAddress;
        uint256 balance;
    }

    struct Wallet {
        mapping(address => uint256) tokenIndex;
        TokenWallet[] tokenList;

        mapping(address => uint256) nftWalletIndex;
        NFTWallet[] nftWalletList;
    }

    uint totalArbSupply;
    mapping(bytes32 => Wallet) wallets;

    function addNFTToken(bytes32 _user, address _tokenContract, uint256 _tokenId) internal {
        Wallet storage wallet = wallets[_user];
        uint index = wallet.nftWalletIndex[_tokenContract];
        if (index == 0) {
            index = wallet.nftWalletList.push(NFTWallet(_tokenContract, new uint256[](0)));
            wallet.nftWalletIndex[_tokenContract] = index;
        }
        NFTWallet storage nftWallet = wallet.nftWalletList[index - 1];
        require(nftWallet.tokenIndex[_tokenId] == 0);
        nftWallet.tokenList.push(_tokenId);
        nftWallet.tokenIndex[_tokenId] = nftWallet.tokenList.length;
    }

    function addToken(bytes32 _user, address _tokenContract, uint256 _value) internal {
        if (_value == 0) {
            return;
        }
        Wallet storage wallet = wallets[_user];
        uint index = wallet.tokenIndex[_tokenContract];
        if (index == 0) {
            index = wallet.tokenList.push(TokenWallet(_tokenContract, 0));
            wallet.tokenIndex[_tokenContract] = index;
        }
        TokenWallet storage tokenWallet = wallet.tokenList[index - 1];
        tokenWallet.balance = tokenWallet.balance.add(_value);
    }

    function removeNFTToken(bytes32 _user, address _tokenContract, uint256 _tokenId) internal {
        Wallet storage wallet = wallets[_user];
        uint walletIndex = wallet.nftWalletIndex[_tokenContract];
        require(walletIndex != 0, "Wallet has no coins from given NFT contract");
        NFTWallet storage nftWallet = wallet.nftWalletList[walletIndex - 1];
        uint tokenIndex = nftWallet.tokenIndex[_tokenId];
        require(tokenIndex != 0, "Wallet does not own specific NFT");
        nftWallet.tokenIndex[nftWallet.tokenList[nftWallet.tokenList.length - 1]] = tokenIndex;
        nftWallet.tokenList[tokenIndex - 1] = nftWallet.tokenList[nftWallet.tokenList.length - 1];
        delete nftWallet.tokenIndex[_tokenId];
        nftWallet.tokenList.length = nftWallet.tokenList.length - 1;
        if (nftWallet.tokenList.length == 0) {
            wallet.nftWalletIndex[wallet.nftWalletList[wallet.nftWalletList.length - 1].contractAddress] = walletIndex;
            wallet.nftWalletList[walletIndex - 1] = wallet.nftWalletList[wallet.nftWalletList.length - 1];
            delete wallet.nftWalletIndex[_tokenContract];
            wallet.nftWalletList.length = wallet.nftWalletList.length - 1;
        }
    }

    function removeToken(bytes32 _user, address _tokenContract, uint256 _value) internal {
        if (_value == 0) {
            return;
        }
        Wallet storage wallet = wallets[_user];
        uint walletIndex = wallet.tokenIndex[_tokenContract];
        require(walletIndex != 0, "Wallet has no coins from given ERC20 contract");
        TokenWallet storage tokenWallet = wallet.tokenList[walletIndex - 1];
        require(_value <= tokenWallet.balance, "Wallet does not own enough ERC20 tokens");
        tokenWallet.balance = tokenWallet.balance.sub(_value);
        if (tokenWallet.balance == 0) {
            wallet.tokenIndex[wallet.tokenList[wallet.tokenList.length - 1].contractAddress] = walletIndex;
            wallet.tokenList[walletIndex - 1] = wallet.tokenList[wallet.tokenList.length - 1];
            delete wallet.tokenIndex[_tokenContract];
            wallet.tokenList.length = wallet.tokenList.length - 1;
        }
    }

    function getTokenBalance(address _tokenContract, bytes32 _owner) public view returns (uint256) {
        Wallet storage wallet = wallets[_owner];
        uint index = wallet.tokenIndex[_tokenContract];
        if (index == 0) {
            return 0;
        }
        return wallet.tokenList[index - 1].balance;
    }

    function hasNFT(address _tokenContract, bytes32 _owner, uint256 _tokenId) public view returns (bool) {
        Wallet storage wallet = wallets[_owner];
        uint index = wallet.nftWalletIndex[_tokenContract];
        if (index == 0) {
            return false;
        }
        return wallet.nftWalletList[index - 1].tokenIndex[_tokenId] != 0;
    }

    function depositEth(bytes32 _destination) external payable {
        addToken(_destination, address(0), msg.value);
    }

    function withdrawEth(uint256 _value) external {
        removeToken(bytes32(bytes20(msg.sender)), address(0), _value);
        msg.sender.transfer(_value);
    }

    function depositERC20(address _tokenContract, uint256 _value) external {
        require(_tokenContract != address(this));
        ERC20(_tokenContract).transferFrom(msg.sender, address(this), _value);
        addToken(bytes32(bytes20(msg.sender)), _tokenContract, _value);
    }

    function withdrawERC20(address _tokenContract, uint256 _value) external {
        require(_tokenContract != address(this));
        removeToken(bytes32(bytes20(msg.sender)), _tokenContract, _value);
        ERC20(_tokenContract).transfer(msg.sender, _value);
    }

    function depositERC721(address _tokenContract, uint256 _tokenId) external {
        require(_tokenContract != address(this));
        ERC721(_tokenContract).transferFrom(msg.sender, address(this), _tokenId);
        addNFTToken(bytes32(bytes20(msg.sender)), _tokenContract, _tokenId);
    }

    function withdrawERC721(address _tokenContract, uint256 _tokenId) external {
        require(_tokenContract != address(this));
        removeNFTToken(bytes32(bytes20(msg.sender)), _tokenContract, _tokenId);
        ERC721(_tokenContract).safeTransferFrom(address(this), msg.sender, _tokenId);
    }

    function transferToken(bytes32 _from, bytes32 _to, address _tokenContract, uint256 _value) public onlyOwner {
        removeToken(_from, _tokenContract, _value);
        addToken(_to, _tokenContract, _value);
    }

    function transferNFT(bytes32 _from, bytes32 _to, address _tokenContract, uint256 _tokenId) public onlyOwner {
        removeNFTToken(_from, _tokenContract, _tokenId);
        addNFTToken(_to, _tokenContract, _tokenId);
    }

    function ownerRemoveToken(bytes32 _user, address _tokenContract, uint256 _value) public onlyOwner {
        removeToken(_user, _tokenContract, _value);
    }

    function hasFunds(
        bytes32 _vmId,
        bytes21[] memory _tokenTypes,
        uint256[] memory _amounts
    ) public {
        for (uint i = 0; i < _tokenTypes.length; i++) {
            if (_tokenTypes[i][20] == 0x01) {
                removeNFTToken(
                    _vmId,
                    address(bytes20(_tokenTypes[i])),
                    _amounts[i]
                );
            } else {
                removeToken(
                    _vmId,
                    address(bytes20(_tokenTypes[i])),
                    _amounts[i]
                );
            }
        }

        for (uint i = 0; i < _tokenTypes.length; i++) {
            if (_tokenTypes[i][20] == 0x01) {
                addNFTToken(
                    _vmId,
                    address(bytes20(_tokenTypes[i])),
                    _amounts[i]
                );
            } else {
                addToken(
                    _vmId,
                    address(bytes20(_tokenTypes[i])),
                    _amounts[i]
                );
            }
        }
    }

    function getTokenBalances(bytes32 _owner) external view returns (address[] memory, uint256[] memory) {
        Wallet storage wallet = wallets[_owner];
        address[] memory addresses = new address[](wallet.tokenList.length);
        uint256[] memory values = new uint256[](addresses.length);
        for (uint i = 0; i < addresses.length; i++) {
            addresses[i] = wallet.tokenList[i].contractAddress;
            values[i] = wallet.tokenList[i].balance;
        }
        return (addresses, values);
    }

    function getNFTTokens(bytes32 _owner) external view returns (address[] memory, uint256[] memory) {
        Wallet storage wallet = wallets[_owner];
        uint totalLength = 0;
        uint i;
        for (i = 0; i < wallet.nftWalletList.length; i++) {
            totalLength += wallet.nftWalletList[i].tokenList.length;
        }
        address[] memory addresses = new address[](totalLength);
        uint256[] memory tokens = new uint256[](totalLength);
        uint count = 0;
        for (i = 0; i < wallet.nftWalletList.length; i++) {
            NFTWallet storage nftWallet = wallet.nftWalletList[i];
            for (uint j = 0; j < nftWallet.tokenList.length; j++) {
                addresses[count] = nftWallet.contractAddress;
                tokens[count] = nftWallet.tokenList[j];
                count++;
            }
        }
        return (addresses, tokens);
    }
}
