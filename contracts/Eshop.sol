pragma solidity ^0.5.0;
/*
当卖家想要上架一个商品时，必须要输入关于该商品的所有信息。定义一个结构类型（struct）来保存商品的信息：
*/
import "./Escrow.sol";

contract eshop{

    struct Bid {
        //维克瑞拍卖　秘密拍卖
        address bidder; //竞价者账户地址
        uint productId; //商品编号
        uint value;     //支付的保证金
        bool revealed;  //是否揭示出价
    } //真实出价不转入合约

    struct Product {
        //商品基本信息
        uint id; //商品编号，全局递增
        string name; //商品的名称
        string category; //商品类别
        string imageLink; //商品图片链接地址
        string descLink; //商品描述链接地址
        string reviewLink; //商品评价信息地址
        //拍卖相关信息
        uint auctionStartTime; //拍卖开始时间 单位秒
        uint auctionEndTime; //拍卖截止时间 单位秒
        uint startPrice; //起拍价格 单位wei
        address payable highestBidder; //出最高价者
        uint highestBid;  //最高出价
        uint secondHighestBid; //次高出价
        uint totalBids; //投标者人数
        ProductStatus status; //商品状态：拍卖中，售出，未售
        ProductCondition condition; //品相：新品、二手

        mapping ( address => mapping (bytes32 => Bid)) bids; //记录商品的所有竞价信息
    }

    // 枚举类型指明商品是销售中，还是已售出，还是未售
    enum ProductStatus { Open, Sold, Unsold }
    // 枚举类型指明商品品相（新品、二手）
    enum ProductCondition { New, Used }
    //商品添加的事件
    event NewProduct(uint _productId,
                    string _name,
                    string  _category,
                    string  _imageLink,
                    string  _descLink,
                    uint _auctionStartTime,
                    uint _auctionEndTime,
                    uint _startPrice,
                    uint _productCondition );

    //使用嵌套mapping来区分不同卖家的商品：
    //键为卖家的账户地址，值为另一个mapping--从商品编号到商品信息的映射
    //映射表智能通过键来提取数据
    mapping (address => mapping(uint => Product)) stores;
    //商品反查表
    //便于根据商品编号找其卖家的账户地址 定义一个从商品编号到卖家账户地址的映射表
    mapping (uint => address payable) productIdInStore;
    //引入托管商品地址，记录商品对应的托管合约实例
    mapping (uint => address) productEscrow;

    //商品编号计数器
    //将其初始化为0，逐渐递增
    // 全局变量并非私有，编号可能并不连续
    uint public productIndex;
    constructor () public { productIndex = 0; }

    //添加商品到商店区块链中
    function addProductToStore (
        string memory _name,             //Product.name - 商品名称
        string memory _category,         //Product.category - 商品类别
        string memory _imageLink,        //Product.imageLink - 商品图片链接
        string memory _descLink,         //Product.descLink - 商品描述文本链接
        uint _auctionStartTime,   //Product.auctionStartTime - 拍卖开始时间
        uint _auctionEndTime,     //Product.auctionEndTime - 拍卖截止时间
        uint _startPrice,         //Product.startPrice - 起拍价格
        uint _productCondition //Product.productCondition - 商品品相
    ) public returns(bool){
        //拍卖截止时间晚于开始时间
        require (_auctionStartTime < _auctionEndTime);
        //商品编号计数器递增
        productIndex += 1;
        //构造Product结构变量
        //局部变量默认是持久化的（storage),存储位置声明为memory,视其为临时变量，函数执行完从内存中删除掉
        Product memory product = Product(productIndex, _name, _category, _imageLink,
                        _descLink, "",_auctionStartTime, _auctionEndTime,
                        _startPrice, address (0), 0, 0, 0, ProductStatus.Open,
                        ProductCondition(_productCondition));
        //存入商品目录表
        stores[msg.sender][productIndex] = product;
        //保存商品反查表
        productIdInStore[productIndex] = msg.sender;

        //添加新商品事件的触发
        emit NewProduct(productIndex, _name, _category, _imageLink, _descLink,
                    _auctionStartTime, _auctionEndTime, _startPrice, _productCondition);
        return true;
    }

    //查看商品信息 不能再加变量堆栈太深！
    //view 只读，不修改合约状态，不会消耗gas
    function getProduct(
        uint _productId //商品编号
    ) view public
    returns (uint, string memory, string memory, string memory, string memory,uint,
            uint, uint, ProductStatus, ProductCondition){
        //利用商品编号提取商品信息
        Product memory product = stores[productIdInStore[_productId]][_productId];
        //按照定义的先后顺序依次返回product结构各成员
        return (product.id, product.name, product.category, product.imageLink,
            product.descLink, product.auctionStartTime,
            product.auctionEndTime, product.startPrice, product.status, product.condition);
    }

    // 评价打分类
    function getReview(
        uint _productId //商品编号
    )view public
    returns (string memory){
        //利用商品编号提取商品信息
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return product.reviewLink;
    }

    //密封出价函数
    function bid(
        uint _productId, //商品编号
        bytes32 _bid     //密封出价哈希值
    ) payable public     //可接受资金支付
    returns (bool) {
        //利用商品编号提取商品数据
        Product storage product = stores[productIdInStore[_productId]][_productId];
        //当前还处于竞价有效期内
        //now 为全局变量，表示当前块的时间戳
        //当该函数被调用，一笔交易将会被创建，会被矿工打包到一个块里
        //每个块都对应有一个时间戳，用来申明这个块被挖出来的时间
        require(now >= product.auctionStartTime);
        require(now <= product.auctionEndTime);
        //支付的保证金高于商品起拍价
        require(msg.value > product.startPrice);
        //竞价人首次递交该出价
        require(product.bids[msg.sender][_bid].bidder == address(0));
        //保存出价信息
        //msg.value表示买家调用合约的bid()方法出价时的保证金
        product.bids[msg.sender][_bid] = Bid(msg.sender, _productId, msg.value, false);
        //更新竞价参与人数
        product.totalBids += 1;
        return true;
    }

    //真实出价函数
    //为验证卖家是否虚报其在竞价期间的真实出价，还需要传入提交密封出价时所用的密文
    function revealBid(
        uint _productId, //商品编号
        string memory _amount,  //真实出价
        string memory _secret   //提交密封出价时使用的密文
    ) public {
        //利用商品编号提取商品数据
        Product storage product = stores[productIdInStore[_productId]][_productId];
        //确认拍卖已经截止
        require(now > product.auctionEndTime);
        //验证声称出价的有效性
        bytes32 sealedBid = keccak256(abi.encodePacked(_amount, _secret));
        Bid memory bidInfo = product.bids[msg.sender][sealedBid];
        require(bidInfo.bidder > address(0));
        require(bidInfo.revealed == false);
        uint refund; //返还金额
        uint amount = stringToUint(_amount); //出价

        if(bidInfo.value < amount) { //如果支付的保证金少于声称的出价，则视为失败
            refund = bidInfo.value;
        } else {
            if (address(product.highestBidder) == address(0)) { //第一个揭示价格的竞价人
                product.highestBidder = msg.sender;
                product.highestBid = amount;
                product.secondHighestBid = product.startPrice;
                refund = bidInfo.value - amount;
            } else {
                if (amount > product.highestBid) { //出价高于已知的最高出价
                    product.secondHighestBid = product.highestBid;
                    product.highestBidder.transfer(product.highestBid);
                    product.highestBidder = msg.sender;
                    product.highestBid = amount;
                    refund = bidInfo.value - amount;
                } else if (amount > product.secondHighestBid) { //出价高于已知的次高出价
                    product.secondHighestBid = amount;
                    refund = amount;
                } else { //如果出价不能胜出前两个价格，则视为失败
                    refund = amount;
                }
            }
        }
        //更新出价揭示标志
        product.bids[msg.sender][sealedBid].revealed = true;

        if (refund > 0) { //原路返还保证金
            msg.sender.transfer(refund);
        }
    }

    //pure承诺该函数不读取不修改状态
    //private私有函数，不需要从合约外部调用这个方法
    //将买家出价声称的字符串转成整型
    function stringToUint(string memory s) pure private returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (uint (uint8(b[i])) >= 48 && uint (uint8(b[i])) <= 57) {
                result = result * 10 + (uint (uint8(b[i])) - 48);
            }
        }
        return result;
    }

    //获取竞价结果
    //函数执行完成后自动清理该变量
    function highestBidderInfo(uint _productId) view public returns (address, uint, uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return (product.highestBidder, product.highestBid, product.secondHighestBid);
    }

    //获取参与者总人数
    function totalBids(uint _productId) view public returns (uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return product.totalBids;
    }

    //最终拍卖结果
    function finalizeAuction(uint _productId) payable public {
        //利用商品编号提取商品信息
        Product storage product = stores[productIdInStore[_productId]][_productId];
        //该商品的拍卖应该已经截止
        require(now > product.auctionEndTime);
        //该商品为首次拍卖，之前也没有流拍
        require(product.status == ProductStatus.Open);
        //方法的调用者是否为胜出的买家
        require(product.highestBidder != msg.sender);
        //调用者也不是卖家
        require(productIdInStore[_productId] != msg.sender);

        //无人参与竞价，流拍
        if (product.totalBids == 0) {
            product.status = ProductStatus.Unsold; //将商品标记为“未出售”
            msg.sender.transfer(msg.value);
        } else {
            //创建托管合约实例并按照次高出价将赢家资金转入托管合约 仲裁人保证金也需转入方便监控
            Escrow escrow = (new Escrow).value(product.secondHighestBid+msg.value)(_productId, product.highestBidder,
                                                productIdInStore[_productId], msg.sender, msg.value);
            productEscrow[_productId] = address(escrow);  //记录托管合约实例的地址
            product.status = ProductStatus.Sold;   //将商品标记为已出售
            uint refund = product.highestBid - product.secondHighestBid; //计算赢家的保证金余额并原路返还
            product.highestBidder.transfer(refund);  //退还资金给买家
        }
    }

    //返还资金给买家
    function releaseAmountToSeller(uint _productId) public {
        Escrow(productEscrow[_productId]).releaseAmountToSeller(msg.sender);
    }

    //释放资金给卖家
    function refundAmountToBuyer(uint _productId) public {
        Escrow(productEscrow[_productId]).refundAmountToBuyer(msg.sender);
    }

    //放弃仲裁人身份
    function abandonToArbiter(uint _productId) public {
        Escrow(productEscrow[_productId]).abandonToArbiter(msg.sender);
    }

    //改变仲裁人身份
    function changeToArbiter(uint _productId) payable public {
        Escrow(productEscrow[_productId]).changeToArbiter.value(msg.value)(msg.sender);
    }

    //惩处违法仲裁人
    function punishToArbiter(uint _productId) public{
        Escrow(productEscrow[_productId]).punishToArbiter();
    }

    //显示托管
    function escrowInfo(uint _productId) view public
     returns (address, address, address, bool, uint, uint) {
        return Escrow(productEscrow[_productId]).escrowInfo();
    }

    //判断该交易是否已被托管
    function isEscrow(uint _productId) view public
        returns (bool){
        if (productEscrow[_productId] > address(0)) {
            return true;
        }
        return false;
    }

    //添加商品评论
    function addReview(uint _productId, string memory _reviewLink) public {
         Product storage product = stores[productIdInStore[_productId]][_productId];
         product.reviewLink =  _reviewLink;
    }

}
//Ps: imageLink和descLink分别与商品的图片和描述信息有关。
//为避免在链上直接存储这两种数据，引入IPFS网络 仅仅在区块链上保存其hash值
//链上直接存储不是不可以，但是价格十分昂贵
//渲染网页时，再利用这些Hash值来获取具体的数据
//Ps2:去中心化密封出价的实现
//去中心化区块链中因为每笔交易都是透明的，所以需要对出价额进行加盐hash值处理
//同时支付不低于出价的保证金，拍卖期间只能看到保证金而已
//Ps3:sha3算法加密，对出价在前端调用sha3函数进行加密传输(5.0换为keccak256)
//Ps4:finalizeAuction()中，由于需要修改合约状态
//故局部变量product使用默认的storage存储，对局部变量product进行修改，将等价地修改其引用的stores状态