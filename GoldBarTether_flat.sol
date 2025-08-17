// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/* --- Minimal Ownable & ERC20 & Chainlink interface (flattened) --- */
abstract contract Context { function _msgSender() internal view virtual returns (address) { return msg.sender; } }
contract Ownable is Context {
    address private _owner; event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _transferOwnership(_msgSender()); }
    modifier onlyOwner(){ require(owner()==_msgSender(),"Ownable: caller is not the owner"); _; }
    function owner() public view returns(address){ return _owner; }
    function transferOwnership(address newOwner) public onlyOwner { require(newOwner!=address(0),"Ownable: new owner is the zero address"); _transferOwnership(newOwner); }
    function _transferOwnership(address newOwner) internal { address oldOwner=_owner; _owner=newOwner; emit OwnershipTransferred(oldOwner,newOwner); }
}
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address a) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address o, address s) external view returns (uint256);
    function approve(address s, uint256 amount) external returns (bool);
    function transferFrom(address f,address t,uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
}
contract ERC20 is Context, IERC20 {
    mapping(address=>uint256) private _balances;
    mapping(address=>mapping(address=>uint256)) private _allowances;
    uint256 private _totalSupply; string private _name; string private _symbol;
    constructor(string memory n,string memory s){_name=n;_symbol=s;}
    function name() public view returns(string memory){return _name;}
    function symbol() public view returns(string memory){return _symbol;}
    function decimals() public pure returns(uint8){return 18;}
    function totalSupply() public view override returns(uint256){return _totalSupply;}
    function balanceOf(address a) public view override returns(uint256){return _balances[a];}
    function transfer(address to,uint256 amount) public override returns(bool){_transfer(_msgSender(),to,amount);return true;}
    function allowance(address o,address s) public view override returns(uint256){return _allowances[o][s];}
    function approve(address s,uint256 amount) public override returns(bool){_approve(_msgSender(),s,amount);return true;}
    function transferFrom(address f,address t,uint256 amount) public override returns(bool){
        uint256 a=_allowances[f][_msgSender()]; require(a>=amount,"ERC20: insufficient allowance");
        _transfer(f,t,amount); unchecked{_approve(f,_msgSender(),a-amount);} return true;
    }
    function _transfer(address f,address t,uint256 amount) internal virtual{
        require(f!=address(0)&&t!=address(0),"ERC20: zero addr");
        uint256 b=_balances[f]; require(b>=amount,"ERC20: exceeds balance");
        unchecked{_balances[f]=b-amount;} _balances[t]+=amount; emit Transfer(f,t,amount);
    }
    function _mint(address to,uint256 amount) internal virtual{
        require(to!=address(0),"ERC20: mint to zero"); _totalSupply+=amount; _balances[to]+=amount; emit Transfer(address(0),to,amount);
    }
    function _approve(address o,address s,uint256 amount) internal virtual{
        require(o!=address(0)&&s!=address(0),"ERC20: zero addr"); _allowances[o][s]=amount; emit Approval(o,s,amount);
    }
}
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
}

/**
 * GoldBarTether (GBT)
 * - Peer-to-peer ERC-20
 * - Cloud-minable (global daily cap: 19,890,927 GBT)
 * - Flat transfer fee to fee receiver
 * - Online price enforcement (syncs Chainlink price daily before actions)
 * - Price spikes >=18% can continue unlimited
 * - Price drops <=6% do not block mining or transfers
 */
contract GoldBarTether is ERC20, Ownable {
    // ===== Constants =====
    uint256 public constant INITIAL_SUPPLY = 999_000_000_000_000_000_000_000_000_000_000_000_000; // 999 sextillion
    uint256 public constant DAILY_GLOBAL_MINE_CAP = 19_890_927 ether; // 19,890,927 GBT max per day
    uint256 public constant TRANSFER_FEE = 0.1 ether;                // flat fee
    address public immutable FEE_RECEIVER;

    // ===== Oracle State =====
    AggregatorV3Interface public priceFeed;
    uint256 public launchTimestamp;

    mapping(uint256 => uint256) public priceHistory; // dayIndex => normalized price
    bool public priceSpiked18OrMore;
    bool public priceDropped6OrMore;

    // ===== Mining State =====
    uint256 public lastMineDay;
    uint256 public minedToday; // total mined today (global)

    // ===== Events =====
    event PriceSynced(uint256 day, uint256 adjustedPrice);
    event Mined(address indexed miner, uint256 amount, uint256 day);
    event FeeTaken(address indexed from, address indexed to, uint256 fee);

    // ===== Constructor =====
    constructor(
        address _priceFeed,
        address _deployer,
        address _feeReceiver
    ) ERC20("GoldBarTether", "GBT") {
        require(_priceFeed != address(0), "Invalid oracle");
        require(_deployer != address(0), "Invalid deployer");
        require(_feeReceiver != address(0), "Invalid fee receiver");

        priceFeed = AggregatorV3Interface(_priceFeed);
        launchTimestamp = block.timestamp;
        FEE_RECEIVER = _feeReceiver;

        _mint(_deployer, INITIAL_SUPPLY); // gas-free initial mint
    }

    // ===== Modifiers =====
    modifier enforcePriceOnline() {
        _syncDailyPrice();
        _;
    }

    // ===== Mining =====
    function mine(uint256 amount) external enforcePriceOnline {
        uint256 today = _currentDay();
        if (today > lastMineDay) {
            lastMineDay = today;
            minedToday = 0;
        }
        require(minedToday + amount <= DAILY_GLOBAL_MINE_CAP, "Daily cap exceeded");
        _mint(msg.sender, amount);
        minedToday += amount;
        emit Mined(msg.sender, amount, today);
    }

    // ===== Oracle Management =====
    function setOracle(address _priceFeed) external onlyOwner {
        require(_priceFeed != address(0), "Invalid oracle");
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function updatePriceFromOracle() external onlyOwner {
        _syncDailyPrice();
    }

    // ===== ERC20 Overrides =====
    function transfer(address to, uint256 value) public override enforcePriceOnline returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override enforcePriceOnline returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(amount > TRANSFER_FEE, "Amount must be > fee");
        uint256 amountAfterFee = amount - TRANSFER_FEE;
        super._transfer(sender, recipient, amountAfterFee);
        super._transfer(sender, FEE_RECEIVER, TRANSFER_FEE);
        emit FeeTaken(sender, FEE_RECEIVER, TRANSFER_FEE);
    }

    // ===== Internal Price Logic =====
    function _syncDailyPrice() internal {
        uint256 day = _currentDay();
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid oracle price");

        uint256 adjustedPrice = _normalizeTo1e18(uint256(price), priceFeed.decimals());

        if (priceHistory[day] == 0) {
            priceHistory[day] = adjustedPrice;

            if (day > 0 && priceHistory[day - 1] > 0) {
                uint256 prev = priceHistory[day - 1];
                // spike >=18%
                priceSpiked18OrMore = adjustedPrice * 100 >= prev * 118;
                // drop <=6%
                priceDropped6OrMore = adjustedPrice * 100 <= prev * 94;
            }
            emit PriceSynced(day, adjustedPrice);
        }
        updatedAt; // silence warning
    }

    function _normalizeTo1e18(uint256 value, uint8 srcDecimals) internal pure returns (uint256) {
        if (srcDecimals == 18) return value;
        if (srcDecimals < 18) return value * (10 ** (18 - srcDecimals));
        return value / (10 ** (srcDecimals - 18));
    }
    function _currentDay() internal view returns (uint256) {
        return (block.timestamp - launchTimestamp) / 1 days;
    }
}
