// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Internal Imports from OpenZeppelin
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract HistoricalArts is ERC721URIStorage, ERC721Holder {
    uint256 private _tokenIds;
    uint256 private _itemsSold;

    uint256 public listingPrice = 0.0025 ether;  // Listing price for minting
    address payable public owner;

    mapping(uint256 => MarketItem) private idMarketItem;
    mapping(address => Creator) private creators;
    mapping(address => uint256) private creatorSoldItems;

    struct MarketItem {
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
        address nftContract;
    }

    struct Creator {
        string name;
        string imageURL;
        string description;
        bool isCreator;
        uint256 totalEarnings;
    }

    event idMarketItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        address nftContract
    );

    // Only the owner of the contract can change specific values like listingPrice
    modifier onlyOwner {
        require(msg.sender == owner, "Only the marketplace owner can change the listing price");
        _;
    }

    // Only creators can call certain functions
    modifier onlyCreators {
        require(creators[msg.sender].isCreator, "Only creators can call this function");
        _;
    }

    constructor() ERC721("Historical ART Token", "HAT") {
        owner = payable(msg.sender); // Contract deployer becomes owner
    }

    /**
     * @dev Register a new creator.
     */
    function createCreator(string memory name, string memory imageURL, string memory description) public {
        require(!creators[msg.sender].isCreator, "Creator already registered");
        creators[msg.sender] = Creator(name, imageURL, description, true, 0);
    }

    /**
     * @dev Update the listing price by the contract owner.
     */
    function updateListingPrice(uint256 _listingPrice) public payable onlyOwner {
        listingPrice = _listingPrice;
    }

    /**
     * @dev Get the current listing price.
     */
    function getListingPrice() public view returns (uint256) {
        return listingPrice;
    }

    /**
     * @dev Create a new token, mint it, and list it for sale in the marketplace.
     */
    function createToken(string memory tokenURI, uint256 price) public payable onlyCreators returns (uint256) {
        require(msg.value == listingPrice, "Listing price required");

        uint256 newTokenId = _tokenIds++;
        _mint(msg.sender, newTokenId);  // Mint the new NFT
        _setTokenURI(newTokenId, tokenURI);  // Set the token URI (metadata)
        createMarketItem(address(this), newTokenId, price, msg.sender);  // List the token on the marketplace

        return newTokenId;
    }

    /**
     * @dev List an already deployed NFT for sale in the marketplace.
     */
    function listExistingNFT(address nftContract, uint256 tokenId, uint256 price) public payable onlyCreators {
        require(msg.value == listingPrice, "Listing price required");

        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);  // Transfer the NFT to the marketplace
        createMarketItem(nftContract, tokenId, price, msg.sender);  // List the token on the marketplace
    }

    /**
     * @dev Create a new market item for sale.
     */
    function createMarketItem(address nftContract, uint256 tokenId, uint256 price, address seller) private {
        require(price > 0, "Price must be at least 1 wei");

        idMarketItem[tokenId] = MarketItem(
            tokenId,
            payable(seller), // Seller is the creator of the item
            payable(address(this)), // Initially, the marketplace owns the token
            price,
            false,
            nftContract
        );

        emit idMarketItemCreated(tokenId, seller, address(this), price, false, nftContract);
    }

    /**
     * @dev Resell a token that the user has previously purchased.
     */
    function reSellToken(address nftContract, uint256 tokenId, uint256 price) public payable onlyCreators {
        require(idMarketItem[tokenId].owner == msg.sender, "Only the item owner can resell it");
        require(msg.value == listingPrice, "Listing price required");

        idMarketItem[tokenId].sold = false;
        idMarketItem[tokenId].price = price;
        idMarketItem[tokenId].seller = payable(msg.sender);
        idMarketItem[tokenId].owner = payable(address(this)); // Marketplace becomes the new owner

        _itemsSold--;  // Reduce the number of sold items
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);  // Transfer ownership back to marketplace
    }

    /**
     * @dev Create a market sale and transfer the token to the buyer.
     */
    function createMarketSale(uint256 tokenId) public payable {
        uint256 price = idMarketItem[tokenId].price;
        require(msg.value == price, "Submit asking price to complete transaction");

        address payable seller = idMarketItem[tokenId].seller;
        idMarketItem[tokenId].owner = payable(msg.sender);  // Buyer becomes the new owner
        idMarketItem[tokenId].sold = true;
        _itemsSold++;  // Increment the number of sold items

        IERC721(idMarketItem[tokenId].nftContract).transferFrom(address(this), msg.sender, tokenId);  // Transfer ownership to buyer

        payable(owner).transfer(listingPrice);  // Transfer listing fee to contract owner
        seller.transfer(msg.value);  // Transfer price to seller

        // Track the number of items sold by the creator
        creatorSoldItems[seller]++;
        // Update the total earnings of the creator
        creators[seller].totalEarnings += msg.value;
    }

    /**
     * @dev Fetch all unsold market items.
     */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _tokenIds;
        uint256 unsoldItemCount = _tokenIds - _itemsSold;
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idMarketItem[i + 1].owner == address(this)) {  // Item is still owned by marketplace
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /**
     * @dev Fetch all tokens owned by the caller.
     */
    function fetchMyArt() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i + 1].owner == msg.sender) {  // Item is owned by the caller
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i + 1].owner == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /**
     * @dev Fetch all items listed by the caller.
     */
    function fetchItemsListed() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i + 1].seller == msg.sender) {  // Item was listed by the caller
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i + 1].seller == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }
}