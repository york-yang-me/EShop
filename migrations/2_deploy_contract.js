const EShop = artifacts.require("eshop");

module.exports = function(deployer) {
  deployer.deploy(EShop);
}