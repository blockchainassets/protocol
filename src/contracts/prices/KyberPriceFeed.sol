pragma solidity ^0.4.21;

import "PriceSource.i.sol";
import "ERC20.i.sol";
import "thing.sol";
import "KyberNetworkProxy.sol";
import "Registry.sol";

/// @title Price Feed Template
/// @author Melonport AG <team@melonport.com>
/// @notice Routes external data to smart contracts
/// @notice Where external data includes sharePrice of Melon funds
/// @notice PriceFeed operator could be staked and sharePrice input validated on chain
contract KyberPriceFeed is PriceSourceInterface, DSThing {

    address public KYBER_NETWORK_PROXY;
    address public QUOTE_ASSET;
    address public UPDATER;
    Registry public REGISTRY;
    uint public MAX_SPREAD;
    address public constant KYBER_ETH_TOKEN = 0x00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee;
    uint public constant KYBER_PRECISION = 18;
    uint public constant VALIDITY_INTERVAL = 2 days;
    uint public lastUpdate;

    // FIELDS

    mapping (address => uint) public prices;

    // METHODS

    // CONSTRUCTOR

    /// @dev Define and register a quote asset against which all prices are measured/based against
    constructor(
        address ofRegistrar,
        address ofKyberNetworkProxy,
        uint ofMaxSpread,
        address ofQuoteAsset
    ) {
        KYBER_NETWORK_PROXY = ofKyberNetworkProxy;
        MAX_SPREAD = ofMaxSpread;
        QUOTE_ASSET = ofQuoteAsset;
        REGISTRY = Registry(ofRegistrar);
        UPDATER = REGISTRY.owner();
    }

    /// @dev Stores zero as a convention for invalid price
    function update() external {
        require(
            msg.sender == REGISTRY.owner() || msg.sender == UPDATER,
            "Only registry owner or updater can call"
        );
        address[] memory assets = REGISTRY.getRegisteredAssets();
        uint[] memory newPrices = new uint[](assets.length);
        for (uint i; i < assets.length; i++) {
            bool isValid;
            uint price;
            (isValid, price) = getKyberPrice(assets[i], QUOTE_ASSET);
            newPrices[i] = isValid ? price : 0;
            prices[assets[i]] = newPrices[i];
        }
        lastUpdate = block.timestamp;
        PriceUpdate(assets, newPrices);
    }

    /// @dev Set updater
    function setUpdater(address _updater) external {
        require(msg.sender == REGISTRY.owner(), "Only registry owner can set");
        UPDATER = _updater;
    }

    // PUBLIC VIEW METHODS

    // FEED INFORMATION

    function getQuoteAsset() public view returns (address) { return QUOTE_ASSET; }

    // PRICES

    /**
    @notice Gets price of an asset multiplied by ten to the power of assetDecimals
    @dev Asset has been registered
    @param _asset Asset for which price should be returned
    @return {
      "price": "Price formatting: mul(exchangePrice, 10 ** decimal), to avoid floating numbers",
      "timestamp": "When the asset's price was updated"
    }
    */
    function getPrice(address _asset)
        public
        view
        returns (uint price, uint timestamp)
    {
        (price, ) =  getReferencePriceInfo(_asset, QUOTE_ASSET);
        timestamp = now;
    }

    function getPrices(address[] _assets)
        public
        view
        returns (uint[], uint[])
    {
        uint[] memory prices = new uint[](_assets.length);
        uint[] memory timestamps = new uint[](_assets.length);
        for (uint i; i < _assets.length; i++) {
            uint price;
            uint timestamp;
            (price, timestamp) = getPrice(_assets[i]);
            prices[i] = price;
            timestamps[i] = timestamp;
        }
        return (prices, timestamps);
    }

    function hasValidPrice(address _asset)
        public
        view
        returns (bool)
    {
        bool isRegistered = REGISTRY.assetIsRegistered(_asset);
        bool isFresh = block.timestamp < add(lastUpdate, VALIDITY_INTERVAL);
        return prices[_asset] != 0 && isRegistered && isFresh;
    }

    function hasValidPrices(address[] _assets)
        public
        view
        returns (bool)
    {
        for (uint i; i < _assets.length; i++) {
            if (!hasValidPrice(_assets[i])) {
                return false;
            }
        }
        return true;
    }

    /**
    @param _baseAsset Address of base asset
    @param _quoteAsset Address of quote asset
    @return {
        "referencePrice": "Quantity of quoteAsset per whole baseAsset",
        "decimals": "Decimal places for quoteAsset"
    }
    */
    function getReferencePriceInfo(address _baseAsset, address _quoteAsset)
        public
        view
        returns (uint referencePrice, uint decimals)
    {
        bool isValid;
        (
            isValid,
            referencePrice,
            decimals
        ) = getRawReferencePriceInfo(_baseAsset, _quoteAsset);
        require(isValid, "Price is not valid");
        return (referencePrice, decimals);
    }

    function getRawReferencePriceInfo(address _baseAsset, address _quoteAsset)
        public
        view
        returns (bool isValid, uint referencePrice, uint decimals)
    {
        isValid = hasValidPrice(_baseAsset) && hasValidPrice(_quoteAsset);
        uint quoteDecimals = ERC20Clone(_quoteAsset).decimals();

        if (prices[_quoteAsset] == 0) {
            return (false, 0, 0);  // return early and avoid revert
        }

        referencePrice = mul(
            prices[_baseAsset],
            10 ** uint(quoteDecimals)
        ) / prices[_quoteAsset];

        return (isValid, referencePrice, quoteDecimals);
    }

    function getPriceInfo(address _asset)
        public
        view
        returns (uint price, uint assetDecimals)
    {
        return getReferencePriceInfo(_asset, QUOTE_ASSET);
    }

    /**
    @notice Gets inverted price of an asset
    @dev Asset has been initialised and its price is non-zero
    @param _asset Asset for which inverted price should be return
    @return {
        "isValid": "Whether the price is fresh, given VALIDITY_INTERVAL",
        "invertedPrice": "Price based (instead of quoted) against QUOTE_ASSET",
        "assetDecimals": "Decimal places for this asset"
    }
    */
    function getInvertedPriceInfo(address _asset)
        public
        view
        returns (uint invertedPrice, uint assetDecimals)
    {
        return getReferencePriceInfo(QUOTE_ASSET, _asset);
    }

    /// @dev Get Kyber representation of ETH if necessary
    function getKyberMaskAsset(address _asset) public returns (address) {
        if (_asset == REGISTRY.nativeAsset()) {
            return KYBER_ETH_TOKEN;
        }
        return _asset;
    }

    function getKyberPrice(address _baseAsset, address _quoteAsset)
        public
        view
        returns (bool isValid, uint kyberPrice)
    {
        address maskedBaseAsset = getKyberMaskAsset(_baseAsset);
        address maskedQuoteAsset = getKyberMaskAsset(_quoteAsset);

        uint bidRate;
        uint bidRateOfReversePair;
        (bidRate,) = KyberNetworkProxy(KYBER_NETWORK_PROXY).getExpectedRate(
            ERC20Clone(maskedBaseAsset),
            ERC20Clone(maskedQuoteAsset),
            REGISTRY.getReserveMin(maskedBaseAsset)
        );
        (bidRateOfReversePair,) = KyberNetworkProxy(KYBER_NETWORK_PROXY).getExpectedRate(
            ERC20Clone(maskedQuoteAsset),
            ERC20Clone(maskedBaseAsset),
            REGISTRY.getReserveMin(maskedQuoteAsset)
        );

        if (bidRate == 0 || bidRateOfReversePair == 0) {
            return (false, 0);  // return early and avoid revert
        }

        uint askRate = 10 ** (KYBER_PRECISION * 2) / bidRateOfReversePair;
        // Check the the spread and average the price on both sides
        uint spreadFromKyber = mul(
            sub(askRate, bidRate),
            10 ** uint(KYBER_PRECISION)
        ) / bidRate;
        uint averagePriceFromKyber = add(bidRate, askRate) / 2;
        kyberPrice = mul(
            averagePriceFromKyber,
            10 ** uint(ERC20Clone(_quoteAsset).decimals()) // use original quote decimals (not defined on mask)
        ) / 10 ** uint(KYBER_PRECISION);

        return (
            spreadFromKyber <= MAX_SPREAD && averagePriceFromKyber != 0,
            kyberPrice
        );
    }

    /// @notice Gets price of Order
    /// @param sellAsset Address of the asset to be sold
    /// @param buyAsset Address of the asset to be bought
    /// @param sellQuantity Quantity in base units being sold of sellAsset
    /// @param buyQuantity Quantity in base units being bought of buyAsset
    /// @return orderPrice Price as determined by an order
    function getOrderPriceInfo(
        address sellAsset,
        address buyAsset,
        uint sellQuantity,
        uint buyQuantity
    )
        public
        view
        returns (uint orderPrice)
    {
        // TODO: decimals
        return mul(buyQuantity, 10 ** uint(ERC20Clone(sellAsset).decimals())) / sellQuantity;
    }

    /// @notice Checks whether data exists for a given asset pair
    /// @dev Prices are only upated against QUOTE_ASSET
    /// @param sellAsset Asset for which check to be done if data exists
    /// @param buyAsset Asset for which check to be done if data exists
    /// @return Whether assets exist for given asset pair
    function existsPriceOnAssetPair(address sellAsset, address buyAsset)
        public
        view
        returns (bool isExistent)
    {
        return
            hasValidPrice(sellAsset) && // Is tradable asset (TODO cleaner) and datafeed delivering data
            hasValidPrice(buyAsset);
    }

    /// @notice Get quantity of toAsset equal in value to given quantity of fromAsset
    function convertQuantity(
        uint fromAssetQuantity,
        address fromAsset,
        address toAsset
    )
        public
        view
        returns (uint)
    {
        uint fromAssetPrice;
        (fromAssetPrice,) = getReferencePriceInfo(fromAsset, toAsset);
        uint fromAssetDecimals = ERC20WithFields(fromAsset).decimals();
        return mul(
            fromAssetQuantity,
            fromAssetPrice
        ) / (10 ** uint(fromAssetDecimals));
    }

    function getLastUpdate() public view returns (uint) { return lastUpdate; }
}
