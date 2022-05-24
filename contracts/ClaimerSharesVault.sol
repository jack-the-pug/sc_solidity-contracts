struct Claimer {
  uint256 principal;
  uint256 shares; // relative to gloabl totalShares
  uint256 totalSupply;
}

struct Depositor {
  uint256 principal;
  uint256 claimerShares; // relative to Claimer.totalSupply
}

contract ClaimerSharesVault {
  uint256 public totalShares;
  IStrategy public strategy;
  address public underlying;
  mapping(address => Claimer) public claimers;
  mapping(address => mapping(address => Depositor)) public depositors; // claimerAdd => depositorAdd => Depositor

  function deposit(
    address claimer,
    uint256 wantAmount
  ) external {
    Claimer storage _claimer = claimers[claimer];
    Depositor storage _depositor = depositors[claimer][msg.sender];

    uint _shares = _amountToShares(wantAmount, totalShares, totalUnderlyingValue());
 
    // global shares is the actual shares
    totalShares += _shares;

    uint256 claimerPricePerShare = _claimer.totalSupply == 0 ? 1e18 : _claimer.shares * 1e18 / _claimer.totalSupply;
    uint claimerShares = _shares * 1e18 / claimerPricePerShare;

    _depositor.principal += wantAmount;
    _depositor.claimerShares += claimerShares;

    // claimer shares is the notional shares
    _claimer.principal += wantAmount;
    _claimer.shares += _shares;
    _claimer.totalSupply += claimerShares;

    underlying.safeTransferFrom(msg.sender, address(this), wantAmount);
  }

  function withdraw(
    address claimer,
    uint256 wantAmount
  ) external {
    Depositor storage _depositor = depositors[claimer][msg.sender];
    Claimer storage _claimer = claimers[claimer];

    if (wantAmount > _depositor.principal) {
      wantAmount = _depositor.principal;
    }

    uint _shares = _amountToShares(wantAmount, totalShares, totalUnderlyingValue());
  
    uint256 claimerPricePerShare = _claimer.shares * 1e18 / _claimer.totalSupply;
    uint claimerSharesToBurn = _shares * 1e18 / claimerPricePerShare;

    // when claimerVault got sufficient shares for all depositors' principal, we ensure claimerSharesToBurn can be burnt
    // in essence, this will lower the claimer vault's pps, in other words, a bailout paid by all other depositors
    uint claimerVaultTotalUnderlyingValue = _claimer.shares * pricePerShare() / 1e12;
    if (claimerVaultTotalUnderlyingValue >= _claimer.principal && claimerSharesToBurn > _depositor.claimerShares) {
      claimerSharesToBurn = _depositor.claimerShares;
    }

    // global shares is the actual shares
    totalShares -= _shares;

    _depositor.principal -= wantAmount;
    _depositor.claimerShares -= claimerSharesToBurn;

    // update states for the _claimer
    _claimer.shares -= _shares;
    _claimer.principal -= wantAmount;
    _claimer.totalSupply -= claimerSharesToBurn;

    // TODO: withdraw from strategy
    underlying.safeTransfer(to, wantAmount);
  }

  function harvest(
    address to
  ) external {
    Claimer storage _claimer = claimers[msg.sender];
    uint claimerVaultTotalUnderlyingValue = _claimer.shares * pricePerShare() / 1e12;

    if (claimerVaultTotalUnderlyingValue > _claimer.principal) {
      yieldAmount = claimerVaultTotalUnderlyingValue - _claimer.principal;
      yieldShares = _amountToShares(yieldAmount);
    }
    
    totalShares -= yieldShares;

    _claimer.yieldDebtPerClaimerShare += yieldAmount / _claimer.totalSupply;
    _claimer.shares -= yieldShares;
    _claimer.sharesDebt += yieldShares12;

    underlying.safeTransfer(to, yieldAmount);
  }

  function _amountToShares(
    uint256 _amount,
    uint256 _totalShares,
    uint256 _totalUnderlyingValue
  ) internal pure returns (uint256) {
    if (_amount == 0) return 0;
    if (_totalShares == 0) return _amount * 1e12;
    return (_amount * _totalShares) / _totalUnderlyingValue;
  }

  function pricePerShare() public view returns (uint256) {
    return 1e12 * totalUnderlyingValue() / totalShares;
  }

  function totalUnderlyingValue() public view returns (uint256) {
    if (address(strategy) != address(0)) {
      return
        underlying.balanceOf(address(this)) + strategy.investedAssets();
    }
    return underlying.balanceOf(address(this));
  }
}