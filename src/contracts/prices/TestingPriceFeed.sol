pragma solidity ^0.4.21;

import "ERC20.i.sol";
import "PriceSource.i.sol";
import "UpdatableFeed.i.sol";
import "math.sol";

/// @notice Intended for testing purposes only
/// @notice Updates and exposes price information
contract TestingPriceFeed is UpdatableFeedInterface, PriceSourceInterface, DSMath {

    struct Data {
        uint price;
        uint timestamp;
    }

    address public QUOTE_ASSET;
    uint public updateId;
    mapping(address => Data) public assetsToPrices;
    mapping(address => uint) public assetsToDecimals;
    bool mockIsRecent = true;
    bool alwaysValid = true;

    constructor(address _quoteAsset, uint _quoteDecimals) {
        QUOTE_ASSET = _quoteAsset;
        setDecimals(_quoteAsset, _quoteDecimals);
    }

    /**
      Input price is how much quote asset you would get
      for one unit of _asset (10**assetDecimals)
     */
    function update(address[] _assets, uint[] _prices) external {
        require(_assets.length == _prices.length, "Array lengths unequal");
        updateId++;
        for (uint i = 0; i < _assets.length; ++i) {
            assetsToPrices[_assets[i]] = Data({
                timestamp: block.timestamp,
                price: _prices[i]
            });
        }
    }

    function getPrice(address ofAsset) view returns (uint price, uint timestamp) {
        Data data = assetsToPrices[ofAsset];
        return (data.price, data.timestamp);
    }

    function getPrices(address[] ofAssets) view returns (uint[], uint[]) {
        uint[] memory prices = new uint[](ofAssets.length);
        uint[] memory timestamps = new uint[](ofAssets.length);
        for (uint i; i < ofAssets.length; i++) {
            uint price;
            uint timestamp;
            (price, timestamp) = getPrice(ofAssets[i]);
            prices[i] = price;
            timestamps[i] = timestamp;
        }
        return (prices, timestamps);
    }

    function getPriceInfo(address ofAsset)
        view
        returns (uint price, uint assetDecimals)
    {
        (price, ) = getPrice(ofAsset);
        assetDecimals = assetsToDecimals[ofAsset];
    }

    function getInvertedPriceInfo(address ofAsset)
        view
        returns (uint invertedPrice, uint assetDecimals)
    {
        uint inputPrice;
        // inputPrice quoted in QUOTE_ASSET and multiplied by 10 ** assetDecimal
        (inputPrice, assetDecimals) = getPriceInfo(ofAsset);

        // outputPrice based in QUOTE_ASSET and multiplied by 10 ** quoteDecimal
        uint quoteDecimals = assetsToDecimals[QUOTE_ASSET];

        return (
            mul(
                10 ** uint(quoteDecimals),
                10 ** uint(assetDecimals)
            ) / inputPrice,
            quoteDecimals
        );
    }

    function setAlwaysValid(bool _state) {
        alwaysValid = _state;
    }

    function setIsRecent(bool _state) {
        mockIsRecent = _state;
    }

    // NB: not permissioned; anyone can change this in a test
    function setDecimals(address _asset, uint _decimal) {
        assetsToDecimals[_asset] = _decimal;
    }

    // needed just to get decimals for prices
    function batchSetDecimals(address[] _assets, uint[] _decimals) {
        require(_assets.length == _decimals.length, "Array lengths unequal");
        for (uint i = 0; i < _assets.length; i++) {
            setDecimals(_assets[i], _decimals[i]);
        }
    }

    function getReferencePriceInfo(address ofBase, address ofQuote)
        view
        returns (uint referencePrice, uint decimal)
    {
        uint quoteDecimals = assetsToDecimals[ofQuote];

        // Price of 1 unit for the pair of same asset
        if (ofBase == ofQuote) {
            return (10 ** quoteDecimals, quoteDecimals);
        }

        referencePrice = mul(
            assetsToPrices[ofBase].price,
            10 ** quoteDecimals
        ) / assetsToPrices[ofQuote].price;

        return (referencePrice, quoteDecimals);
    }

    function getOrderPriceInfo(
        address sellAsset,
        address buyAsset,
        uint sellQuantity,
        uint buyQuantity
    )
        view
        returns (uint orderPrice)
    {
        return mul(buyQuantity, 10 ** assetsToDecimals[sellAsset]) / sellQuantity;
    }

    /// @notice Doesn't check validity as TestingPriceFeed has no validity variable
    /// @param _asset Asset in registrar
    /// @return isValid Price information ofAsset is recent
    function hasValidPrice(address _asset)
        view
        returns (bool isValid)
    {
        var (price, ) = getPrice(_asset);
        return alwaysValid || price != 0;
    }

    function hasValidPrices(address[] _assets)
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

    /// @notice Checks whether data exists for a given asset pair
    /// @dev Prices are only upated against QUOTE_ASSET
    /// @param sellAsset Asset for which check to be done if data exists
    /// @param buyAsset Asset for which check to be done if data exists
    /// @return Whether assets exist for given asset pair
    function existsPriceOnAssetPair(address sellAsset, address buyAsset)
        view
        returns (bool isExistent)
    {
        return
            hasValidPrice(sellAsset) &&
            hasValidPrice(buyAsset);
    }

    function getLastUpdateId() public view returns (uint) { return updateId; }
    function getQuoteAsset() public view returns (address) { return QUOTE_ASSET; }

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
        ) / (10 ** fromAssetDecimals);
    }
}

