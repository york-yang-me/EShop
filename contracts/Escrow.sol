pragma solidity ^0.5.0;

contract Escrow {

    uint public productId; //商品编号
    address payable public buyer; //买家
    address payable public seller; //卖家
    address payable public arbiter; //第三方
    uint public amount; //托管金额
    uint public arbiterFund; //仲裁人资金
    mapping (address => bool ) releaseAmount; //记录参与者是否已经投过票
    uint public releaseCount;  //有几个参与者同意释放资金
    bool public fundsDisbursed;  //资金是否已经流出托管账户
    mapping (address => bool)refundAmount; //记录参与者是否已经投过票
    uint public refundCount; //有几个参与者同意返还资金

    constructor (uint _productId, address payable _buyer,
                address payable _seller, address payable _arbiter, uint _arbiterFund) payable public {
        //保存商品编号
        productId = _productId;
        //保存参与三方的账户地址
        buyer = _buyer;
        seller = _seller;
        arbiter = _arbiter;
        //只有声明了payable的函数，msg.value才有效
        amount = msg.value-_arbiterFund;
        arbiterFund = _arbiterFund;
    }

    //释放资金给卖家
    function releaseAmountToSeller(address caller) public {
        //如果资金已经流出，则终止函数执行
        require(!fundsDisbursed);
        //只有托管合约的参与三方可以投票决定资金的流向，而且每个人只能投一次票
        if ((caller == buyer || caller == seller || caller == arbiter) &&
            releaseAmount[caller] != true) {
            releaseAmount[caller] = true;
            releaseCount += 1;

        }
        //如果同意向卖家释放资金的人超过半数，就立刻将99%托管资金转入卖家账户
        // 同时1%交给仲裁人作为交易评判奖励
        if (releaseCount == 2) {
            seller.transfer(amount*99/100);
            arbiter.transfer(amount/100+arbiterFund);
            fundsDisbursed = true;
        }
    }

    //返还资金给买家
    function refundAmountToBuyer(address caller) public{
        //如果资金已经流出，则终止函数执行
        require(!fundsDisbursed);
        //只有托管合约的参与三方可以投票决定资金的流向，而且每个人只能投一次票
        if ((caller == buyer || caller == seller || caller == arbiter) &&
            refundAmount[caller] != true) {
            refundAmount[caller] = true;
            refundCount += 1;
        }

        //如果同意卖家释放资金的人超过半数，将就立刻将99%托管资金转入买家账户
        //同时1%交给仲裁人作为交易评判奖励
        if(refundCount == 2) {
            buyer.transfer(amount*99/100);
            arbiter.transfer(amount*99/100+arbiterFund);
            fundsDisbursed = true;
        }
    }

    //放弃仲裁人身份
    function abandonToArbiter(address caller) public {
        //如果资金已经流出，则终止函数执行
        require(!fundsDisbursed);
        //判断当前用户身份
        require(caller == arbiter);
        arbiter.transfer(arbiterFund);
        arbiter = address(0);
    }

    //改变仲裁人身份
    function changeToArbiter(address payable caller) payable public {
        //如果资金已经流出，则终止函数执行
        require(!fundsDisbursed);
        //判断当前交易是否缺仲裁人
        require(arbiter == address(0));
        //新仲裁人不能是买方或者卖方
        require(caller != buyer);
        require(caller != seller);
        arbiter = caller;
        arbiterFund = msg.value;
        amount = amount-arbiterFund;
    }

    //惩处非法仲裁人
    function punishToArbiter() public{
         //如果资金已经流出，则终止函数执行
        require(!fundsDisbursed);
        arbiter = address(0);
    }

    //托管信息显示
    function escrowInfo() view public returns (address, address, address, bool, uint, uint) {
        return (buyer, seller, arbiter, fundsDisbursed, releaseCount, refundCount);
    }

}
