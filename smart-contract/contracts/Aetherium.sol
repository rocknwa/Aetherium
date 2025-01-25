// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Internal Imports from OpenZeppelin
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "./NFT.sol";

contract Aetherium is ERC721URIStorage, ERC721Holder {
    uint256 private _tokenIds;
    uint256 private _itemsSold;
    uint256 private _marketItemIds;

    uint256 public listingFeePercentage = 2;  // Listing fee percentage (e.g., 2%)
    address payable public owner;

    mapping(uint256 => MarketItem) private idMarketItem;
    mapping(address => Creator) private creators;
    mapping(address => uint256) private creatorSoldItems;

    struct MarketItem {
        uint256 marketItemId;
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
        uint256 indexed marketItemId,
        uint256 indexed tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        address nftContract
    );

    // Only the owner of the contract can change specific values like listingFeePercentage
    modifier onlyOwner {
        require(msg.sender == owner, "Only the marketplace owner can change the listing fee percentage");
        _;
    }

    // Only creators can call certain functions
    modifier onlyCreators {
        require(creators[msg.sender].isCreator, "Only creators can call this function");
        _;
    }

    constructor() ERC721("Aetherium", "AETH") {
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
     * @dev Update the listing fee percentage by the contract owner.
     */
    function updateListingFeePercentage(uint256 _listingFeePercentage) public onlyOwner {
        listingFeePercentage = _listingFeePercentage;
    }

    /**
     * @dev Get the current listing fee percentage.
     */
    function getListingFeePercentage() public view returns (uint256) {
        return listingFeePercentage;
    }

    /**
     * @dev Create a new token, mint it, and list it for sale in the marketplace.
     */
    function createToken(string memory tokenURI, uint256 price) public onlyCreators returns (uint256) {
        uint256 newTokenId = _tokenIds++;
        _mint(msg.sender, newTokenId);  // Mint the new NFT
        _setTokenURI(newTokenId, tokenURI);  // Set the token URI (metadata)
        createMarketItem(address(this), newTokenId, price, msg.sender);  // List the token on the marketplace

        return newTokenId;
    }

    /**
     * @dev List an already deployed NFT for sale in the marketplace.
     */
    function listExistingNFT(address nftContract, uint256 tokenId, uint256 price) public onlyCreators {
        IERC721(nftContract).transferFrom(msg.sender, address(this), tokenId);  // Transfer the NFT to the marketplace
        createMarketItem(nftContract, tokenId, price, msg.sender);  // List the token on the marketplace
    }

    function createCustomNFT(string memory _tokenURI, string memory _title, string memory _symbol, uint price) public onlyCreators {
        // Deploy a new NFT contract
        NFT nft = new NFT(_title, _symbol, _tokenURI);
        nft.mintNFT(msg.sender);
        uint256 tokenId = 0;
        tokenId++;
        IERC721(address(nft)).transferFrom(msg.sender, address(this), tokenId);  // Transfer the NFT to the marketplace
        createMarketItem(address(nft), tokenId, price, msg.sender); 
    }

    /**
     * @dev Create a new market item for sale.
     */
    function createMarketItem(address nftContract, uint256 tokenId, uint256 price, address seller) private {
        require(price > 0, "Price must be at least 1 wei");

        uint256 marketItemId = _marketItemIds++;
        
        idMarketItem[marketItemId] = MarketItem(
            marketItemId,
            tokenId,
            payable(seller), // Seller is the creator of the item
            payable(address(this)), // Initially, the marketplace owns the token
            price,
            false,
            nftContract
        );

        emit idMarketItemCreated(marketItemId, tokenId, seller, address(this), price, false, nftContract);
    }

    /**
     * @dev Resell a token that the user has previously purchased.
     */
    function reSellToken(address nftContract, uint256 marketItemId, uint256 price) public onlyCreators {
        MarketItem storage item = idMarketItem[marketItemId];
        require(item.owner == msg.sender, "Only the item owner can resell it");

        item.sold = false;
        item.price = price;
        item.seller = payable(msg.sender);
        item.owner = payable(address(this)); // Marketplace becomes the new owner

        _itemsSold--;  // Reduce the number of sold items
        IERC721(nftContract).transferFrom(msg.sender, address(this), item.tokenId);  // Transfer ownership back to marketplace
    }

    /**
     * @dev Create a market sale and transfer the token to the buyer.
     */
    function createMarketSale(uint256 marketItemId) public payable {
        MarketItem storage item = idMarketItem[marketItemId];
        uint256 price = item.price;
        require(msg.value == price, "Submit asking price to complete transaction");

        address payable seller = item.seller;
        item.owner = payable(msg.sender);  // Buyer becomes the new owner
        item.sold = true;
        _itemsSold++;  // Increment the number of sold items

        IERC721(item.nftContract).transferFrom(address(this), msg.sender, item.tokenId);  // Transfer ownership to buyer

        uint256 listingFee = (price * listingFeePercentage) / 100;
        uint256 sellerAmount = price - listingFee;

        payable(owner).transfer(listingFee);  // Transfer listing fee to contract owner
        seller.transfer(sellerAmount);  // Transfer remaining amount to seller

        // Track the number of items sold by the creator
        creatorSoldItems[seller]++;
        // Update the total earnings of the creator
        creators[seller].totalEarnings += sellerAmount;
    }

    /**
     * @dev Fetch all unsold market items.
     */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _marketItemIds;
        uint256 unsoldItemCount = _marketItemIds - _itemsSold;
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idMarketItem[i].owner == address(this)) {  // Item is still owned by marketplace
                MarketItem storage currentItem = idMarketItem[i];
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
        uint256 totalItemCount = _marketItemIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i].owner == msg.sender) {  // Item is owned by the caller
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i].owner == msg.sender) {
                MarketItem storage currentItem = idMarketItem[i];
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
        uint256 totalItemCount = _marketItemIds;
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i].seller == msg.sender) {  // Item was listed by the caller
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idMarketItem[i].seller == msg.sender) {
                MarketItem storage currentItem = idMarketItem[i];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

} 