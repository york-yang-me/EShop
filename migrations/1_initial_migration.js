const Migrations = artifacts.require("Migrations");
//实现部署的脚本
module.exports = function(deployer) {
  deployer.deploy(Migrations);
};
