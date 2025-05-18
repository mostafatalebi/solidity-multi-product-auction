const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("Auction", (m) => {
  const account1 = m.getAccount(0);
  const auction = m.contract("Auction", [], { from: account1 });

  return { auction };
});
