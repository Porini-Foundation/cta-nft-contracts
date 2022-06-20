//  CTANFT Fixed Price Marketplace contract
// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./CTANFT.sol";

interface ICTANFT {
	function initialize(string memory _name, string memory _uri, address creator, bool bPublic) external;
	function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;
	function balanceOf(address account, uint256 id) external view returns (uint256);
	function creatorOf(uint256 id) external view returns (address);
	function creatorFee(uint256 id) external view returns (uint256);
}

contract CTANFTMarket is Ownable, ERC1155Holder {
    using SafeMath for uint256;
	using EnumerableSet for EnumerableSet.AddressSet;

	uint256 constant public PERCENTS_DIVIDER = 100;
	uint256 public swapFee = 1;	
	address public feeAddress; 

    /* Pairs to swap NFT _id => price */
	struct Pair {
		uint256 pairId;
		address collection;
		uint256 tokenId;
		address creator;
		address owner;
		uint256 balance;
		uint256 price;
		uint256 creatorFee;
		bool bValid;
	}

    bool private initialisable;
	address[] public collections;
	// collection address => creator address
	mapping(uint256 => Pair) public pairs;
	uint256 public currentPairId = 0;

	/** Events */
    event CollectionCreated(address collection_address, address owner, string name, string uri, bool isPublic);
    event ItemListed(Pair item);
	event ItemDelisted(address collection, uint256 tokenId, uint256 pairId);
    event ItemSwapped(address buyer, uint256 id, uint256 amount, Pair item);

	constructor () {		
		initialisable = true;
	}
	function initialize(address _feeAddress) external onlyOwner {
		require(initialisable, "initialize() can be called only one time.");
		initialisable = false;
		feeAddress = _feeAddress;
		createCollection("CTANFT", "https://ipfs.io/ipfs/QmSSfM6KVBk1JRfjbGxQu5AUqZKpAshM5Don3h5J7tcnft", true);		
	}

	function setFeeAddress(address _address, uint256 _swapFee) external onlyOwner {
		require(_address != address(0x0), "invalid address");
        feeAddress = _address;
		swapFee = _swapFee;
    }

	function createCollection(string memory _name, string memory _uri, bool bPublic) public returns(address collection) {
		bytes memory bytecode = type(CTANFT).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(_uri, _name, block.timestamp));
        assembly {
            collection := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ICTANFT(collection).initialize(_name, _uri, msg.sender, bPublic);
		collections.push(collection);
		emit CollectionCreated(collection, msg.sender, _name, _uri, bPublic);
	}

    function list(address _collection, uint256 _tokenId, uint256 _amount, uint256 _price) public {
		require(_price > 0, "invalid price");
		require(_amount > 0, "invalid amount");
		ICTANFT nft = ICTANFT(_collection);
        uint256 nft_token_balance = nft.balanceOf(msg.sender, _tokenId);
		require(nft_token_balance >= _amount, "invalid amount : amount have to be smaller than NFT balance");
		
		nft.safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "List");

		currentPairId = currentPairId.add(2);
		pairs[currentPairId].pairId = currentPairId;
		pairs[currentPairId].collection = _collection;
		pairs[currentPairId].tokenId = _tokenId;
		pairs[currentPairId].creator = nft.creatorOf(_tokenId);
		pairs[currentPairId].owner = msg.sender;
		pairs[currentPairId].balance = _amount;
		pairs[currentPairId].price = _price;
		pairs[currentPairId].creatorFee = nft.creatorFee(_tokenId);
		pairs[currentPairId].bValid = true;

        emit ItemListed(pairs[currentPairId]);
    }

	function delist(uint256 _id) external {
		require(pairs[_id].bValid, "invalid Pair id");
		require(pairs[_id].owner == msg.sender || msg.sender == owner(), "only owner can delist");

		ICTANFT(pairs[_id].collection).safeTransferFrom(address(this), pairs[_id].owner, pairs[_id].tokenId, pairs[_id].balance, "delist Marketplace");
		pairs[_id].balance = 0;
		pairs[_id].bValid = false;

		emit ItemDelisted(pairs[_id].collection, pairs[_id].tokenId, _id);
	}

    function buy(uint256 _id, uint256 _amount) external payable {
        require(pairs[_id].bValid, "invalid Pair id");
		require(pairs[_id].balance >= _amount, "insufficient NFT balance");

		Pair memory item = pairs[_id];
		uint256 tokenAmount = item.price.mul(_amount);
		
		require(msg.value >= tokenAmount, "too small amount");

		// transfer coin to admin
		if(swapFee > 0) {
			payable(feeAddress).transfer(tokenAmount.mul(swapFee).div(PERCENTS_DIVIDER));			
		}
		// transfer coin to creator
		if(item.creatorFee > 0) {
			payable(item.creator).transfer(tokenAmount.mul(item.creatorFee).div(PERCENTS_DIVIDER));			
		}
		// transfer coin to owner
		uint256 ownerPercent = PERCENTS_DIVIDER.sub(swapFee).sub(item.creatorFee);
		payable(item.owner).transfer(tokenAmount.mul(ownerPercent).div(PERCENTS_DIVIDER));		

		// transfer NFT token to buyer
		ICTANFT(pairs[_id].collection).safeTransferFrom(address(this), msg.sender, item.tokenId, _amount, "buy from Marketplace");

		pairs[_id].balance = pairs[_id].balance.sub(_amount);
		if (pairs[_id].balance == 0) {
			pairs[_id].bValid = false;
		}		
        emit ItemSwapped(msg.sender, _id, _amount, pairs[_id]);
    }

	function withdrawRemained() public onlyOwner {
		uint balance = address(this).balance;
		require(balance > 0, "insufficient balance");
		payable(msg.sender).transfer(balance);
	}
}