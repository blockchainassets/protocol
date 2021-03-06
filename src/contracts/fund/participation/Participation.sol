pragma solidity ^0.4.21;

import "Spoke.sol";
import "Shares.sol";
import "Accounting.sol";
import "Vault.sol";
import "ERC20.i.sol";
import "Factory.sol";
import "math.sol";
import "PriceSource.i.sol";
import "AmguConsumer.sol";
import "Participation.i.sol";

/// @notice Entry and exit point for investors
contract Participation is ParticipationInterface, DSMath, AmguConsumer, Spoke {
    struct Request {
        address investmentAsset;
        uint investmentAmount;
        uint requestedShares;
        uint timestamp;
    }

    uint constant public SHARES_DECIMALS = 18;
    uint constant public REQUEST_LIFESPAN = 1 days;

    mapping (address => Request) public requests;
    mapping (address => bool) public investAllowed;
    mapping (address => bool) public hasInvested; // for information purposes only (read)

    address[] public historicalInvestors; // for information purposes only (read)

    constructor(address _hub, address[] _defaultAssets, address _registry) Spoke(_hub) {
        routes.registry = _registry;
        _enableInvestment(_defaultAssets);
    }

    function() public payable {}

    function _enableInvestment(address[] _assets) internal {
        for (uint i = 0; i < _assets.length; i++) {
            require(
                Registry(routes.registry).assetIsRegistered(_assets[i]),
                "Asset not registered"
            );
            investAllowed[_assets[i]] = true;
        }
        emit EnableInvestment(_assets);
    }

    function enableInvestment(address[] _assets) external auth {
        _enableInvestment(_assets);
    }

    function disableInvestment(address[] _assets) external auth {
        for (uint i = 0; i < _assets.length; i++) {
            investAllowed[_assets[i]] = false;
            emit DisableInvestment(_assets);
        }
    }

    function hasRequest(address _who) public view returns (bool) {
        return requests[_who].timestamp > 0;
    }

    function hasExpiredRequest(address _who) public view returns (bool) {
        return block.timestamp > add(requests[_who].timestamp, REQUEST_LIFESPAN);
    }

    /// @notice Whether request is OK and invest delay is being respected
    /// @dev Request valid if price update happened since request and not expired
    /// @dev If no shares exist and not expired, request can be executed immediately
    function hasValidRequest(address _who) public view returns (bool) {
        PriceSourceInterface priceSource = PriceSourceInterface(routes.priceSource);
        bool delayRespectedOrNoShares = requests[_who].timestamp < priceSource.getLastUpdate() ||
            Shares(routes.shares).totalSupply() == 0;

        return hasRequest(_who) &&
            delayRespectedOrNoShares &&
            !hasExpiredRequest(_who) &&
            requests[_who].investmentAmount > 0 &&
            requests[_who].requestedShares > 0;
    }

    function requestInvestment(
        uint requestedShares,
        uint investmentAmount,
        address investmentAsset
    )
        external
        notShutDown
        payable
        amguPayable(true)
        onlyInitialized
    {
        PolicyManager(routes.policyManager).preValidate(
            bytes4(sha3("requestInvestment(address)")),
            [msg.sender, address(0), address(0), investmentAsset, address(0)],
            [uint(0), uint(0), uint(0)],
            bytes32(0)
        );
        require(
            investAllowed[investmentAsset],
            "Investment not allowed in this asset"
        );
        require(
            msg.value >= Registry(routes.registry).incentive(),
            "Incorrect incentive amount"
        );
        require(
            ERC20(investmentAsset).transferFrom(msg.sender, this, investmentAmount),
            "InvestmentAsset transfer failed"
        );
        require(
            requests[msg.sender].timestamp == 0,
            "Only one request can exist at a time"
        );
        requests[msg.sender] = Request({
            investmentAsset: investmentAsset,
            investmentAmount: investmentAmount,
            requestedShares: requestedShares,
            timestamp: block.timestamp
        });
        PolicyManager(routes.policyManager).postValidate(
            bytes4(sha3("requestInvestment(address)")),
            [msg.sender, address(0), address(0), investmentAsset, address(0)],
            [uint(0), uint(0), uint(0)],
            bytes32(0)
        );

        emit InvestmentRequest(
            msg.sender,
            investmentAsset,
            requestedShares,
            investmentAmount
        );
    }

    /// @notice Can only cancel when no price, request expired or fund shut down
    /// @dev Only request owner can cancel their request
    function cancelRequest() external payable amguPayable(false) {
        require(hasRequest(msg.sender), "No request to cancel");
        PriceSourceInterface priceSource = PriceSourceInterface(routes.priceSource);
        Request request = requests[msg.sender];
        require(
            !priceSource.hasValidPrice(request.investmentAsset) ||
            hasExpiredRequest(msg.sender) ||
            hub.isShutDown(),
            "No cancellation condition was met"
        );
        ERC20 investmentAsset = ERC20(request.investmentAsset);
        uint investmentAmount = request.investmentAmount;
        delete requests[msg.sender];
        msg.sender.transfer(Registry(routes.registry).incentive());
        require(
            investmentAsset.transfer(msg.sender, investmentAmount),
            "InvestmentAsset refund failed"
        );

        emit CancelRequest(msg.sender);
    }

    function executeRequestFor(address requestOwner)
        external
        notShutDown
        amguPayable(false)
        payable
    {
        Request memory request = requests[requestOwner];
        require(
            hasValidRequest(requestOwner),
            "No valid request for this address"
        );
        require(
            PriceSourceInterface(routes.priceSource).hasValidPrice(request.investmentAsset),
            "Price not valid"
        );

        FeeManager(routes.feeManager).rewardManagementFee();

        uint totalShareCostInInvestmentAsset = Accounting(routes.accounting)
            .getShareCostInAsset(
                request.requestedShares,
                request.investmentAsset
            );

        require(
            totalShareCostInInvestmentAsset <= request.investmentAmount,
            "Invested amount too low"
        );
        require(  // send necessary amount of investmentAsset to vault
            ERC20(request.investmentAsset).transfer(
                address(routes.vault),
                totalShareCostInInvestmentAsset
            ),
            "Failed to transfer investment asset to vault"
        );

        uint investmentAssetChange = sub(
            request.investmentAmount,
            totalShareCostInInvestmentAsset
        );

        if (investmentAssetChange > 0) {
            require(  // return investmentAsset change to request owner
                ERC20(request.investmentAsset).transfer(
                    requestOwner,
                    investmentAssetChange
                ),
                "Failed to return investmentAsset change"
            );
        }

        msg.sender.transfer(Registry(routes.registry).incentive());

        Shares(routes.shares).createFor(requestOwner, request.requestedShares);
        Accounting(routes.accounting).addAssetToOwnedAssets(request.investmentAsset);

        if (!hasInvested[request.investmentAsset]) {
            historicalInvestors.push(requestOwner);
        }

        emit RequestExecution(
            requestOwner,
            msg.sender,
            request.investmentAsset,
            request.investmentAmount,
            request.requestedShares
        );
        delete requests[requestOwner];
    }

    function getOwedPerformanceFees(uint shareQuantity)
        public
        view
        returns (uint remainingShareQuantity)
    {
        Shares shares = Shares(routes.shares);

        if (msg.sender == hub.manager()) {
            return 0;
        }

        uint totalPerformanceFee = FeeManager(routes.feeManager).performanceFeeAmount();
        // The denominator is augmented because performanceFeeAmount() accounts for inflation
        // Since shares are directly transferred, we don't need to account for inflation in this case
        uint performanceFeePortion = mul(
            totalPerformanceFee,
            shareQuantity
        ) / add(shares.totalSupply(), totalPerformanceFee);
        return performanceFeePortion;
    }

    /// @dev "Happy path" (no asset throws & quantity available)
    /// @notice Redeem all shares and across all assets
    function redeem() external {
        uint ownedShares = Shares(routes.shares).balanceOf(msg.sender);
        redeemQuantity(ownedShares);
    }

    /// @notice Redeem shareQuantity across all assets
    function redeemQuantity(uint shareQuantity) public {
        address[] memory assetList;
        (, assetList) = Accounting(routes.accounting).getFundHoldings();
        redeemWithConstraints(shareQuantity, assetList);
    }

    // TODO: reconsider the scenario where the user has enough funds to force shutdown on a large trade (any way around this?)
    /// @dev Redeem only selected assets (used only when an asset throws)
    function redeemWithConstraints(uint shareQuantity, address[] requestedAssets) public {
        Shares shares = Shares(routes.shares);
        require(
            shares.balanceOf(msg.sender) >= shareQuantity &&
            shares.balanceOf(msg.sender) > 0,
            "Sender does not have enough shares to fulfill request"
        );

        uint owedPerformanceFees = 0;
        if (
            PriceSourceInterface(routes.priceSource).hasValidPrices(requestedAssets)
        ) {
            FeeManager(routes.feeManager).rewardManagementFee();
            owedPerformanceFees = getOwedPerformanceFees(shareQuantity);
            shares.destroyFor(msg.sender, owedPerformanceFees);
            shares.createFor(hub.manager(), owedPerformanceFees);
        }
        uint remainingShareQuantity = sub(shareQuantity, owedPerformanceFees);

        address ofAsset;
        uint[] memory ownershipQuantities = new uint[](requestedAssets.length);
        address[] memory redeemedAssets = new address[](requestedAssets.length);
        // Check whether enough assets held by fund
        Accounting accounting = Accounting(routes.accounting);
        for (uint i = 0; i < requestedAssets.length; ++i) {
            ofAsset = requestedAssets[i];
            if (ofAsset == address(0)) continue;
            require(
                accounting.isInAssetList(ofAsset),
                "Requested asset not in asset list"
            );
            for (uint j = 0; j < redeemedAssets.length; j++) {
                require(
                    ofAsset != redeemedAssets[j],
                    "Asset can only be redeemed once"
                );
            }
            redeemedAssets[i] = ofAsset;
            uint quantityHeld = accounting.assetHoldings(ofAsset);
            if (quantityHeld == 0) continue;

            // participant's ownership percentage of asset holdings
            ownershipQuantities[i] = mul(quantityHeld, remainingShareQuantity) / shares.totalSupply();
        }

        shares.destroyFor(msg.sender, remainingShareQuantity);

        // Transfer owned assets
        for (uint k = 0; k < requestedAssets.length; ++k) {
            ofAsset = requestedAssets[k];
            if (ownershipQuantities[k] == 0) {
                continue;
            } else {
                Vault(routes.vault).withdraw(ofAsset, ownershipQuantities[k]);
                require(
                    ERC20(ofAsset).transfer(msg.sender, ownershipQuantities[k]),
                    "Asset transfer failed"
                );
            }
        }
        emit Redemption(
            msg.sender,
            requestedAssets,
            ownershipQuantities,
            remainingShareQuantity
        );
    }

    function getHistoricalInvestors() external view returns (address[]) {
        return historicalInvestors;
    }
}

contract ParticipationFactory is Factory {
    event NewInstance(
        address indexed hub,
        address indexed instance,
        address[] defaultAssets,
        address registry
    );

    function createInstance(address _hub, address[] _defaultAssets, address _registry)
        external
        returns (address)
    {
        address participation = new Participation(_hub, _defaultAssets, _registry);
        childExists[participation] = true;
        emit NewInstance(_hub, participation, _defaultAssets, _registry);
        return participation;
    }
}

