// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Import the ERC721URIStorage extension from OpenZeppelin, which includes storage based token URI management
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

// Import the Ownable contract from OpenZeppelin, which provides basic authorization control
import "@openzeppelin/contracts/access/Ownable.sol";
 

// Define the main contract SongNFT that inherits from ERC721URIStorage and Ownable
contract NFT is ERC721URIStorage, Ownable(msg.sender) {
    uint256 private _currentTokenId; // Private variable to track the current token ID
     string public tokenURI;
    
    // Constructor to initialize the contract with the provided details
    constructor(
        string memory _name, 
        string memory _symbol, 
        string memory _tokenURI 
    ) ERC721(_name, _symbol) {
        _currentTokenId = 0; 
        tokenURI = _tokenURI;            // Initialize current token ID to 0
    }

    // Function to mint a new NFT
    function mintNFT(address _to) external payable returns (uint256) {
        _currentTokenId++; // Increment current token ID
        uint256 newTokenId = _currentTokenId; // Assign new token ID

        // Mint the NFT to the specified address
        _safeMint(_to, newTokenId);
        _setTokenURI(newTokenId, tokenURI); // Set the token URI to the audio URI

        return newTokenId; // Return the new token ID
    }  
}