//  CTANFT token
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CTANFT is ERC1155, AccessControl {
    using SafeMath for uint256;

    struct Item {
        uint256 id;
        address creator;
        string uri;
        uint256 supply;
        uint256 royalty;
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public constant PERCENTS_DIVIDER = 100;
	uint256 constant public FEE_MAX_PERCENT = 20; // 20 %
    uint256 constant public FEE_MIN_PERCENT = 5; // 5 %

    string public name;
    bool public isPublic;
    address public factory;
    address public owner;
    uint256 public currentID;
    mapping (uint256 => Item) public Items;


    event ItemCreated(uint256 id, string uri, uint256 supply, address creator, uint256 royalty);

    event CollectionUriUpdated(string collection_uri);    
    event CollectionNameUpdated(string collection_name);
    event CollectionPublicUpdated(bool isPublic);
    event TokenUriUpdated(uint256 id, string uri);

    constructor() ERC1155("CTANFT") {
        factory = msg.sender;
    }

    /**
		Initialize from Swap contract
	 */
    function initialize(string memory _name, string memory _uri, address creator, bool bPublic ) external {
        require(msg.sender == factory, "Only for factory");
        _setURI(_uri);
        name = _name;
        owner = creator;
        isPublic = bPublic;

        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        _setupRole(MINTER_ROLE, owner);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, AccessControl) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
		Change Collection URI
	 */
    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
        emit CollectionUriUpdated(newuri);
        
    }

    /**
		Change Collection Name
	 */
    function setName(string memory newname) public onlyOwner {
        name = newname;
        emit CollectionNameUpdated(newname);
    }

    /**
		Make collection as Public
	 */
    function setPublic(bool bPublic) public onlyOwner {
        isPublic = bPublic;
        emit CollectionPublicUpdated(bPublic);
    }

    function uri(uint256 _id) public view override returns (string memory) {
        require(_exists(_id), "ERC1155Tradable#uri: NONEXISTENT_TOKEN");
        // We have to convert string to bytes to check for existence

        bytes memory customUriBytes = bytes(Items[_id].uri);
        if (customUriBytes.length > 0) {
            return Items[_id].uri;
        } else {
            return super.uri(_id);
        }
    }

    /**
     * @dev Returns the total quantity for a token ID
     * @param _id uint256 ID of the token to query
     * @return amount of token in existence
     */
    function totalSupply(uint256 _id) public view returns (uint256) {
        require(_exists(_id), "ERC1155Tradable#uri: NONEXISTENT_TOKEN");
        return Items[_id].supply;        
    }

    /**
     * @dev Will update the base URI for the token
     * @param _tokenId The token to update. _msgSender() must be its creator.
     * @param _newURI New URI for the token.
     */
    function setCustomURI(uint256 _tokenId, string memory _newURI)
        public onlyOwner        
    {        
        Items[_tokenId].uri = _newURI;       
        emit TokenUriUpdated(_tokenId, _newURI);        
    }

    function setOwner(address new_owner)
        public onlyOwner        
    {        
        owner = new_owner;        
        _setupRole(DEFAULT_ADMIN_ROLE, new_owner);
        _setupRole(MINTER_ROLE, new_owner);        
    }

    /**
		Create Card - Only Minters
	 */
    function addItem( uint256 supply, uint256 royalty, string memory _uri ) public returns (uint256) {
        require( hasRole(MINTER_ROLE, msg.sender) || isPublic,
            "Only minter can add item"
        );
        require(supply > 0, "supply can not be 0");
        require(royalty <= FEE_MAX_PERCENT, "too big royalties");
        require(royalty >= FEE_MIN_PERCENT, "too small royalties");
        
        currentID = currentID.add(1);
        if (supply > 0) {
            _mint(msg.sender, currentID, supply, "Mint");
        }

        Items[currentID] = Item(currentID, msg.sender, _uri, supply, royalty);
        emit ItemCreated(currentID, _uri, supply, msg.sender, royalty);
        return currentID;
    }


    function burn(address from, uint256 id, uint256 amount) public returns(bool){
		uint256 nft_token_balance = balanceOf(msg.sender, id);
		require(nft_token_balance > 0, "Only owner can burn");
        require(nft_token_balance >= amount, "invalid amount : amount have to be smaller than the balance");		
		_burn(from, id, amount);
        Items[id].supply = Items[id].supply - amount;
		return true;
	}

    function creatorOf(uint256 id) public view returns (address) {
        return Items[id].creator;
    }

    function creatorFee(uint256 id) public view returns (uint256) {
        return Items[id].royalty;
    }

    modifier onlyOwner() {
        require(owner == _msgSender(), "caller is not the owner");
        _;
    }

    function _exists(uint256 _id) internal view returns (bool) {
        return _id <= currentID;
    }

    /**
     * @dev Require _msgSender() to be the creator of the token id
     */
    modifier creatorOnly(uint256 _id) {
        require(
            Items[_id].creator == _msgSender(),
            "ERC1155Tradable#creatorOnly: ONLY_CREATOR_ALLOWED"
        );
        _;
    }
}
