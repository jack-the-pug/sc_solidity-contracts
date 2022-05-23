struct Claimer {
  uint256 principal;
  uint256 shares;
  uint256 settledYieldShares;
  uint256 yieldDebtShares;
}

struct Depositor {
  uint256 principal;
  uint256 shares;
}

contract Vault {
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

    uint ratio = _claimer.shares == 0 ? 1e12: 1e12 * _shares / (_claimer.shares - _claimer.yieldDebtShares);
    uint notionalAddedShares = _claimer.shares == 0 ? _shares: _claimer.shares * ratio / 1e12;

    // global shares is the actual shares
    totalShares += _shares;

    _depositor.principal += wantAmount;
    // depositor shares is the notional shares, relative to the claimer
    _depositor.shares += notionalAddedShares;

    // claimer shares is the notional shares
    _claimer.principal += wantAmount;
    _claimer.shares += notionalAddedShares;
    _claimer.yieldDebtShares += _claimer.yieldDebtShares * ratio / 1e12;

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

    uint ratio =  1e12 * _shares / (_claimer.shares - _claimer.yieldDebtShares);
    uint notionalSharesToBurn = _claimer.shares * ratio / 1e12;

    require(_depositor.shares > notionalSharesToBurn);

    // global shares is the actual shares
    totalShares -= _shares;

    _depositor.principal -= wantAmount;
    _depositor.shares -= notionalSharesToBurn;

    // update states for the _claimer
    _claimer.principal -= wantAmount;
    _claimer.shares -= notionalSharesToBurn;
    _claimer.yieldDebtShares -= _claimer.yieldDebtShares * ratio / 1e12;

    // TODO: withdraw from strategy
    underlying.safeTransfer(to, wantAmount);
  }

  function harvest(
    address to
  ) external {
    Claimer storage _claimer = claimers[msg.sender];
    (uint yieldAmount, uint yieldShares) = _settle(claimer);
    
    totalShares -= _settledYieldShares;

    _claimer.yieldDebt += yieldAmount;
    _claimer.yieldDebtShares += _settledYieldShares;

    underlying.safeTransfer(to, yieldAmount);
  }

  function _settle(
    address claimer
  ) internal returns (uint yieldAmount, uint yieldShares) {
    Claimer storage _claimer = claimers[msg.sender];
    uint actualUnderlyingValue = _claimer.shares * pricePerShare() / 1e12;

    uint watermark = _claimer.principal + _claimer.yieldDebt;
    if (actualUnderlyingValue > watermark) {
      yieldAmount = actualUnderlyingValue - watermark;
      yieldShares = _amountToShares(yieldAmount);
    }
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