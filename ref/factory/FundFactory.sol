pragma solidity ^0.4.21;


import "../fund/accounting/Accounting.sol";
import "../fund/fees/FeeManager.sol";
import "../fund/hub/Hub.sol";
import "../fund/participation/Participation.sol";
import "../fund/shares/Shares.sol";
import "../fund/trading/Trading.sol";
import "../fund/vault/Vault.sol";
import "../../../src/policies/Manager.sol";

// TODO: integrate with existing infrastructure (version, governance, etc.)
/// @notice Creates fund components and links them together
contract FundFactory {

    address public defaultPriceSource;
    AccountingFactory public accountingFactory;
    FeeManagerFactory public feeManagerFactory;
    ParticipationFactory public participationFactory;
    // PolicyManagerFactory public policyManagerFactory;
    SharesFactory public sharesFactory;
    TradingFactory public tradingFactory;
    VaultFactory public vaultFactory;

    address[] public funds;
    mapping (address => address) public managersToFunds;

    struct FundSettings {
        address[] exchanges;
        address[] adapters;
        address[] defaultAssets;
        bool[] takesCustody;
        address priceSource;
        address[] accountingControllers;
        address[] sharesControllers;
        address[] vaultControllers;
    }
    FundSettings temporarySettings;

    constructor(
        AccountingFactory _accountingFactory,
        FeeManagerFactory _feeManagerFactory,
        ParticipationFactory _participationFactory,
        SharesFactory _sharesFactory,
        TradingFactory _tradingFactory,
        VaultFactory _vaultFactory
    ) {
        accountingFactory = _accountingFactory;
        feeManagerFactory = _feeManagerFactory;
        participationFactory = _participationFactory;
        sharesFactory = _sharesFactory;
        tradingFactory = _tradingFactory;
        vaultFactory = _vaultFactory;
    }

    function setupFund(
        // string _name,
        // address _quoteAsset,
        // address _compliance,
        // address[] _policies,
        // address[] _fees,
        address[] _exchanges,
        address[] _adapters,
        address[] _defaultAssets,
        bool[] _takesCustody,
        address _priceSource
    )
        public
    {
        require(managersToFunds[msg.sender] == address(0));
        temporarySettings.exchanges = _exchanges;
        temporarySettings.adapters = _adapters;
        temporarySettings.defaultAssets = _defaultAssets;
        temporarySettings.takesCustody = _takesCustody;
        temporarySettings.priceSource = _priceSource;
        Hub hub = new Hub(msg.sender);
        address feeManager = feeManagerFactory.createInstance(hub);
        address participation = participationFactory.createInstance(hub);
        temporarySettings.accountingControllers = [participation];
        address accounting = accountingFactory.createInstance(hub, temporarySettings.accountingControllers, temporarySettings.defaultAssets);
        // address policyManager = address(0);
        // address policyManager = policyManagerFactory.createInstance(hub, mockAddresses);
        temporarySettings.sharesControllers = [participation, feeManager];
        address shares = sharesFactory.createInstance(hub, temporarySettings.sharesControllers);
        address trading = tradingFactory.createInstance(hub, temporarySettings.exchanges, temporarySettings.adapters, temporarySettings.takesCustody);
        // temporarySettings.vaultControllers = [participation, trading];
        address vault = vaultFactory.createInstance(hub, temporarySettings.defaultAssets);
        // address priceSource = defaultPriceSource;
        // address canonicalRegistrar = defaultPriceSource;
        // address version = address(0);
        hub.setComponents(
            accounting,
            feeManager,
            participation,
            address(0),
            shares,
            trading,
            vault,
            temporarySettings.priceSource,
            temporarySettings.priceSource,
            address(0)
        );
        funds.push(hub);
        managersToFunds[msg.sender] = hub;
        delete temporarySettings;
    }

    function getFundById(uint withId) public view returns (address) { return funds[withId]; }
    function getLastFundId() public view returns (uint) { return funds.length - 1; }
}

