pragma solidity ^0.8.26;
// SPDX-License-Identifier: GPL-1.0-or-later
import "solidity-json-writer/contracts/JsonWriter.sol";


struct Bid {
        address buyer;
        uint productCode; // name of the item being bid
        uint amount;
        bool put;
}

enum ActivationType { Manual, Temporal }
enum StartStatus { NotStarted, Started, Closed }

// these types are used for custom errors
enum EntityType { Owner, Bid, Product, Bidder }

contract Auction {

    // if temporal, then using setAuctionTimings() function
    // the owner can set start and end date for the auction. 
    // if manual, the owner can start an auction ONLY ONCE
    // and then can end it. 
    ActivationType auctionStartType;

    // this flag is ignored if startType is 
    // set to Temporal
    StartStatus auctionStartStatus = StartStatus.NotStarted;

    event BidPlaced(
        uint productCode,        
        uint amount
    );    

    using JsonWriter for JsonWriter.Json;
    
    address public owner;
    
    // you cannot add more than this amount of
    // products for bidding
    uint private maxProductsCount = 3;

    // no bid for no product can be lower 
    // than this amount. 
    uint private minimumAllowedBid = 1000000 wei;

    mapping (address => bool) public allowedBuyers;

    // unix timestamp of auction start time
    uint auctionStartTime;
    
    // unix timestamp of auction end time
    uint auctionEndTime;

    uint private minimumDurationOfAuction;    

    struct Product {
        uint code;
        uint startingPrice;
        bool exists;
    }

    // any call to addProduct() will add a new product
    // to this array. Only maxProductsCount amount is allowed
    mapping (uint => Product) public productsMap;
    
    // this is used to keep track of currently live products
    // + and - with each addition/removal
    uint public liveProductsCount = 0;

    uint[] public productsKeys;


    // currently put bids, a map of productCode => buyerAddress => Bid
    mapping (uint => mapping (address => Bid)) public currentBids;

    // the winners for each item
    mapping (uint => Bid) winningBids;


    // any eth transfered through bid() function
    // will be kept here. This includes all
    // previous bids upon which the user has
    // put newer (higher) bids. User needs to 
    // call withdraw() to get the unused eth of his/her
    mapping (address => uint) private balances;

    // keeps track of deposited eth by bidders.
    // depositing happens when a bid is placed using
    // bid() function (there is no direct way to deposit unless
    // for a specific product).
    // if a bidder calls withdraw(), only the difference
    // between this deposit and his/her balance in 
    // balances[] storage would be transfered. The amount
    // here will be locked until the end of auction for
    // corresponding bids. After the auction ends, the user's
    // won bids will be subtracted from deposit and the rest will
    // be available for withdrawing (withdraw() must be called by user)
    mapping (address => uint)  biddersDeposit;

    error ErrAuctionIsManual();
    error ErrAuctionIsTemporal();
    error ErrAuctionNotStarted();     
    error ErrAuctionClosed();    
    error ErrAuctionStarted(); 
    error ErrAuctionNotActive(); // this means either not started or it is closed     
    error ErrAuctionCannotBeStarted(); // either has already started or has been already clsoed
    error ErrProductNotFound(); 
    error ErrBidderNotFound();
    error ErrDuplicateBidder();    
    error ErrBidTooLow();    
    error ErrBidCannotBeLowerThanPrevious(); // a bidder cannot rebid with a lower value
    error ErrWithdrawFailed();
    error ErrOutOfBalance();
    error ErrTooManyProducts();
    error ErrBadProductCode();
    error ErrAuctionNotYetClosed();
    error ErrDurTooShort();
    error ErrForbidden();

    modifier onlyOwner {
        require(msg.sender == owner, ErrForbidden());
        _;
    }

    modifier authorizedBidder {
        require(allowedBuyers[msg.sender] == true, ErrForbidden());
        _;
    }

    constructor(ActivationType _startType){
        auctionStartType = _startType;
        owner = msg.sender;
        minimumDurationOfAuction = 30 * 60; // 30 minutes
        allowedBuyers[owner] = true;
    }


    function getCurrentBids(uint productCode, address bidderAddress) public view onlyOwner returns (uint) {
        require(currentBids[productCode][bidderAddress].put == true, ErrProductNotFound());
        return currentBids[productCode][bidderAddress].amount;
    }


    function getHighestBid(uint productCode) public view onlyOwner returns (uint) {
        require(winningBids[productCode].put == true, ErrProductNotFound());
        return winningBids[productCode].amount;
    }

    
    //
    function startAuction() external onlyOwner {
        require(auctionStartType == ActivationType.Manual, ErrAuctionIsTemporal());
        require(auctionStartStatus == StartStatus.NotStarted, ErrAuctionCannotBeStarted());
        auctionStartStatus = StartStatus.Started;
    }

     function closeAuction() external onlyOwner {
        require(auctionStartType == ActivationType.Manual, ErrAuctionIsTemporal());
        require(auctionStartStatus == StartStatus.Started, ErrAuctionNotStarted());
        auctionStartStatus = StartStatus.Started;
    }


    function setAuctionTiming(uint start, uint end) external onlyOwner {
        require(auctionStartType == ActivationType.Temporal && (start < end && end - start >= minimumDurationOfAuction), ErrDurTooShort());

        auctionStartTime = start;
        auctionEndTime = end;
    }

    // this function is used to authorize an entity to
    // be able to participate in the auction
    function authorize(address toBeBuyer) external onlyOwner {
        require(allowedBuyers[toBeBuyer] == false,ErrDuplicateBidder());

        allowedBuyers[toBeBuyer] = true;
    }

    function unauthorize(address toBeBuyer) external onlyOwner {
        require(allowedBuyers[toBeBuyer] == true,ErrBidderNotFound());
        delete allowedBuyers[toBeBuyer];
    }

    // allows bidding using owner's account on behalf of someone else.
    // Doing this allows skipping signer part and use someone else's address
    // and bid it. It, however, still requires you to have authorized the bidder user
    // beforehead. 
    // this function is useful for backend systems where the process needs to be
    // automated or integrated into their server (without needing the client side
    // of the app to be involved with business logic [signing etc.])
    function bidAs(uint productCode, address bidder) external payable authorizedBidder {
        _doBid(productCode, bidder);
    }

    // bidding doesn't handle any sort of refund or withdrawal. If the bidder
    // has attempted several bids, for each individual bid, the amount of ether
    // should be sent along this function call. To withdraw his/her fund, the bidder
    // needs to call withdraw function.
    function bid(uint productCode) external payable authorizedBidder {
        _doBid(productCode, msg.sender);
    }

    function _doBid(uint productCode, address bidder) internal  {
        require(allowedBuyers[bidder] == true, ErrForbidden());
        if(auctionStartType == ActivationType.Temporal){
            require(block.timestamp > auctionStartTime, ErrAuctionNotStarted());
            require(block.timestamp < auctionEndTime, ErrAuctionClosed());
        } else if(auctionStartType == ActivationType.Manual) {
            require(auctionStartStatus == StartStatus.Started, ErrAuctionNotActive());
        }
        require(productsMap[productCode].exists == true, ErrProductNotFound());
        uint amount = msg.value;
        require(amount >= minimumAllowedBid, ErrBidTooLow());

        if(currentBids[productCode][bidder].put == true){
            require(currentBids[productCode][bidder].amount < amount, ErrBidCannotBeLowerThanPrevious());
             biddersDeposit[bidder] -= currentBids[productCode][bidder].amount;
             biddersDeposit[bidder] += amount;
            currentBids[productCode][bidder].amount = amount;
        } else {
             biddersDeposit[bidder] += amount;
            currentBids[productCode][bidder] = Bid({ 
                buyer: bidder,
                productCode: productCode,
                amount: amount,
            put: true}); 
        }

        if(winningBids[productCode].amount < amount) {
            winningBids[productCode] = Bid({ 
                buyer: bidder,
                productCode: productCode,
                amount: amount,
                put: true});
        }

        emit BidPlaced(productCode, amount);

        balances[bidder] += amount;
    }

    function getMyBalance() external view authorizedBidder returns (uint) {
        return balances[msg.sender];
    }
    
    function withdraw() external authorizedBidder {
        _doWithdraw(msg.sender);
    }

    // only owner can call this function and transfer the deposit
    // of a bidder to its address
    function withdrawAs(address bidder) external onlyOwner {
        _doWithdraw(bidder);
    }

    function _doWithdraw(address bidder) private {
        require(allowedBuyers[bidder] == true, ErrForbidden());
        require(balances[bidder] > 0, ErrOutOfBalance());
        uint spending =  biddersDeposit[bidder];
        uint remainder = balances[bidder] - spending;
        balances[bidder] -= remainder;
        require(remainder > 0, ErrOutOfBalance());
        require(payable(bidder).send(remainder) == true, ErrWithdrawFailed());
    }

    // adds/removes a product form the auction. It allows adding/removing product only before
    // an acution starts
    // isRemove if true, removes the product
    function product(uint productCode, uint startingBidPrice, bool isRemove) external onlyOwner {
        if(isRemove == false) {
            addProduct(productCode, startingBidPrice);
        } else {
            removeProduct(productCode);
        }
    }

    function addProduct(uint productCode, uint startingBidPrice) internal {
            if(auctionStartType == ActivationType.Temporal) {
                require(block.timestamp < auctionStartTime, ErrAuctionNotStarted());
            } else if (auctionStartType == ActivationType.Manual) {
                require(auctionStartStatus == StartStatus.NotStarted, ErrAuctionStarted());
            }
            
            require(productsKeys.length < maxProductsCount, ErrTooManyProducts());
            require(productCode > 0, ErrBadProductCode());
            if(productsMap[productCode].exists == true){
                productsMap[productCode].startingPrice = startingBidPrice;
            } else {
                productsMap[productCode] = Product({code: productCode, startingPrice: startingBidPrice, exists: true});
                productsKeys.push(productCode);
                liveProductsCount++;
            }
    }

    function removeProduct(uint productCode) internal {
            if(auctionStartType == ActivationType.Temporal) {
                require(block.timestamp < auctionStartTime, ErrAuctionNotStarted());
            } else if (auctionStartType == ActivationType.Manual) {
                require(auctionStartStatus == StartStatus.NotStarted, ErrAuctionStarted());
            }
            require(productsMap[productCode].exists == true, ErrProductNotFound());
            require(productCode > 0, ErrBadProductCode());
            if(productsKeys.length == 1) {
                productsKeys[0] = 0;
            } else {
                for(uint i = 0; i < productsKeys.length; i++) {
                if(productsKeys[i] != productCode) {
                    uint lastElement = productsKeys[productsKeys.length-1];
                    productsKeys[productsKeys.length-1] = 0;
                    productsKeys[i] = lastElement;
                    productsKeys.pop();
                    break;
                }
            }
            }
            
            delete productsMap[productCode];
            liveProductsCount--;
    }

    // returns list of winners
    function getWinners() public view authorizedBidder returns(string memory)  {
        require(block.timestamp > auctionEndTime, ErrAuctionNotYetClosed());
        JsonWriter.Json memory writer;
        writer = writer.writeStartArray();
        for(uint i = 0; i < productsKeys.length; i++) {
            if(winningBids[productsKeys[i]].put == true) {
                writer = writer.writeStartObject();
                writer = writer.writeUintProperty("productCode", winningBids[productsKeys[i]].productCode);
                writer = writer.writeUintProperty("amount", winningBids[productsKeys[i]].amount);
                writer = writer.writeAddressProperty("winner", winningBids[productsKeys[i]].buyer);
                writer = writer.writeEndObject();
            }            
        }
        writer = writer.writeEndArray();

        return writer.value;
    }

    receive() external payable {}
}