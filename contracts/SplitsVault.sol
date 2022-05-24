struct Depositor {
  uint shares;
  uint lastPricePerShare;
}

contract SplitsVault {
  uint public totalShares;
  IStrategy public strategy;
  address public underlying;

  mapping(address => Depositor) public depositors;
  mapping(address => uint) public claimer;

  function calculateYieldInShare(address _depositor) public view returns (uint) {
    uint lastPricePerShare = depositors[_depositor].lastPricePerShare;
    uint currentPricePerShare = pricePerShare();
    if (currentPricePerShare <= lastPricePerShare) {
        return 0;
    }
    return depositors[_depositor].shares * (currentPricePerShare - lastPricePerShare) / currentPricePerShare;
  }

  function distributeYieldToClaimers(ClaimerParams[] calldata claimers) internal {
    uint _shareAmount = calculateYieldInShare(msg.sender);
    if (_shareAmount == 0) {
      return;
    }
    depositors[msg.sender].lastPricePerShare = pricePerShare();
    depositors[msg.sender].shares -= _shareAmount;

    uint accumulatedAmount;
    for (uint i; i < claimers.length; ++i) {
      ClaimerParams memory claimerData = claimers[i];
      if (claimerData.pct == 0) revert VaultClaimPercentageCannotBe0();
      // if it's the last claim, just grab all remaining amount, instead
      // of relying on percentages
      uint shareAmountToClaimer = i == claimers.length - 1
          ? _shareAmount - accumulatedAmount
          : _shareAmount.pctOf(claimerData.pct);
      accumulatedAmount += shareAmountToClaimer;
      claimer[claimerData.claimer] += shareAmountToClaimer;
    }
  }

  function deposit(uint wantAmount, ClaimerParams[] calldata claimers)
    external
  {  
    Depositor storage depositor = depositors[msg.sender];
    distributeYieldToClaimers(claimers);

    uint currentPricePerShare = pricePerShare();
    uint _shareAmount = wantAmount * 1e12 / currentPricePerShare;
    if (depositors[msg.sender].shares == 0) {
      depositors[msg.sender].lastPricePerShare = currentPricePerShare;
    }
    depositors[msg.sender].shares += _shareAmount;
    totalShares += _shareAmount;

    underlying.safeTransferFrom(msg.sender, address(this), wantAmount);
  }

  function withdraw(uint share, ClaimerParams[] calldata claimers, address _to)
    external
  {
    Depositor storage depositor = depositors[msg.sender];
    distributeYieldToClaimers(claimers);
    
    uint amount = share * pricePerShare() / 1e12;

    depositors[msg.sender].shares -= share;
    totalShares -= share;

    // TODO: withdraw from the strategy if needed
    underlying.safeTransfer(_to, amount);
  }

  function claimYield(address _to) external {
    if (_to == address(0)) revert VaultDestinationCannotBe0Address();

    uint claimerShare = claimer[msg.sender];

    if (claimerShare == 0) return;

    // TODO: charge perf fee
    uint yield = claimerShare * pricePerShare();

    claimer[msg.sender] = 0;
    totalShares -= claimerShare;

    underlying.safeTransfer(_to, yield);
  }

  function pricePerShare() public view returns (uint) {
    return totalShares == 0 ? 1e12: 1e12 * totalUnderlyingValue() / totalShares;
  }

  function totalUnderlyingValue() public view returns (uint) {
    if (address(strategy) != address(0)) {
    return
      underlying.balanceOf(address(this)) + strategy.investedAssets();
    }
    return underlying.balanceOf(address(this));
  }
}