## Multi-Product Auction
This ethereum smart contract enables you (as the owner) to start a multi product auction. Each product can have its own
starting price (in eth). 

### Features
- Allows authorizing a list of bidders
- Allows setting start and end time for the auction, or starting/stopping manually (this is a constructor time flag)
- Allows defining limited number of products for the auction
- Each bidder must send eth along with his/her bid (this is considered as the amount of the bid)
- An owner can do bid or withdraw on behalf of the user. Useful for third part backend systems
- Any lost bid can be withdrawn after the auction ends. 


Functions `authorize()` and `unauthorize()` are used for auth an unauthing a user. 

Functions `bid()`, `bidAs()`, `withdraw()` and `withdrawAs()` are used for interacting with the auction.

Function `product()` is used for adding/removing the product from the auction. Only works if the auction
has not yet started.

And there are a couple of other utility methods which you can find by reading the source code.


### Tests
There are test covering almost most of the functions of the contract. The tests are hardhat test. You need to install nodejs to run it.

```bash
npx hardhat compile # for compiling the contracgt
npx hardhat test # for running the tests
```
### Integration
There is another go project which uses this contract and offers APIs (for demonstration only, no authentication etc.), which
you can find at: https://github.com/mostafatalebi/go-eth-auctions