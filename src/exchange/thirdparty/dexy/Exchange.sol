pragma solidity ^0.4.13;

import "./Vault.sol";

interface ExchangeInterface {

    event Cancelled(bytes32 indexed hash);

    event Traded(
        bytes32 indexed hash,
        address tokenGive,
        uint amountGive,
        address tokenGet,
        uint amountGet,
        address maker,
        address taker
    );

    event Ordered(
        address user,
        address tokenGive,
        address tokenGet,
        uint amountGive,
        uint amountGet,
        uint expires,
        uint nonce
    );

    function trade(address[3] addresses, uint[4] values, bytes signature, uint maxFillAmount) external;
    function cancel(address[3] addresses, uint[4] values) external;
    function order(address[2] addresses, uint[4] values) external;

    function canTrade(address[3] addresses, uint[4] values, bytes signature)
        external
        view
        returns (bool);

    function availableAmount(address[3] addresses, uint[4] values) external view returns (uint);
    function filled(address user, bytes32 hash) external view returns (uint);
    function isOrdered(address user, bytes32 hash) public view returns (bool);
    function vault() public view returns (VaultInterface);

}

library OrderLibrary {

    bytes32 constant public HASH_SCHEME = keccak256(
        "address Token Get",
        "uint Amount Get",
        "address Token Give",
        "uint Amount Give",
        "uint Expires",
        "uint Nonce",
        "address User",
        "address Exchange"
    );

    struct Order {
        address user;
        address tokenGive;
        address tokenGet;
        uint amountGive;
        uint amountGet;
        uint expires;
        uint nonce;
    }

    /// @dev Hashes the order.
    /// @param order Order to be hashed.
    /// @return hash result
    function hash(Order memory order) internal view returns (bytes32) {
        return keccak256(
            HASH_SCHEME,
            keccak256(
                order.tokenGet,
                order.amountGet,
                order.tokenGive,
                order.amountGive,
                order.expires,
                order.nonce,
                order.user,
                this
            )
        );
    }

    /// @dev Creates order struct from value arrays.
    /// @param addresses Array of trade's user, tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    /// @return Order struct
    function createOrder(address[3] addresses, uint[4] values) internal pure returns (Order memory) {
        return Order({
            user: addresses[0],
            tokenGive: addresses[1],
            tokenGet: addresses[2],
            amountGive: values[0],
            amountGet: values[1],
            expires: values[2],
            nonce: values[3]
        });
    }
}

library SignatureValidator {

    enum SignatureMode {
        EIP712,
        GETH,
        TREZOR
    }

    /// @dev Validates that a hash was signed by a specified signer.
    /// @param hash Hash which was signed.
    /// @param signer Address of the signer.
    /// @param signature ECDSA signature along with the mode (0 = EIP712, 1 = Geth, 2 = Trezor) {mode}{v}{r}{s}.
    /// @return Returns whether signature is from a specified user.
    function isValidSignature(bytes32 hash, address signer, bytes signature) internal pure returns (bool) {
        require(signature.length == 66);
        SignatureMode mode = SignatureMode(uint8(signature[0]));

        uint8 v = uint8(signature[1]);
        bytes32 r;
        bytes32 s;
        assembly {
            r := mload(add(signature, 34))
            s := mload(add(signature, 66))
        }

        if (mode == SignatureMode.GETH) {
            hash = keccak256("\x19Ethereum Signed Message:\n32", hash);
        } else if (mode == SignatureMode.TREZOR) {
            hash = keccak256("\x19Ethereum Signed Message:\n\x20", hash);
        }

        return ecrecover(hash, v, r, s) == signer;
    }
}

contract Exchange is Ownable, ExchangeInterface {

    using SafeMath for *;
    using OrderLibrary for OrderLibrary.Order;

    uint256 constant public MAX_FEE = 5000000000000000; // 0.5% ((0.5 / 100) * 10**18)

    VaultInterface public vault;

    uint public takerFee = 0;
    address public feeAccount;

    mapping (address => mapping (bytes32 => bool)) private orders;
    mapping (address => mapping (bytes32 => uint)) private fills;
    mapping (bytes32 => bool) private cancelled;

    function Exchange(uint _takerFee, address _feeAccount, VaultInterface _vault) public {
        require(address(_vault) != 0x0);
        setFees(_takerFee);
        setFeeAccount(_feeAccount);
        vault = _vault;
    }

    /// @dev Withdraws tokens accidentally sent to this contract.
    /// @param token Address of the token to withdraw.
    /// @param amount Amount of tokens to withdraw.
    function withdraw(address token, uint amount) external onlyOwner {
        if (token == 0x0) {
            msg.sender.transfer(amount);
            return;
        }

        ERC20(token).transfer(msg.sender, amount);
    }

    /// @dev Takes an order.
    /// @param addresses Array of trade's user, tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    /// @param signature Signed order along with signature mode.
    /// @param maxFillAmount Maximum amount of the order to be filled.
    function trade(address[3] addresses, uint[4] values, bytes signature, uint maxFillAmount) external {
        OrderLibrary.Order memory order = OrderLibrary.createOrder(addresses, values);

        require(msg.sender != order.user);
        bytes32 hash = order.hash();

        require(order.tokenGive != order.tokenGet);
        require(canTrade(order, signature, hash));

        uint filledAmount = performTrade(order, maxFillAmount, hash);

        emit Traded(
            hash,
            order.tokenGive,
            order.amountGive * filledAmount / order.amountGet,
            order.tokenGet,
            filledAmount,
            order.user,
            msg.sender
        );
    }

    /// @dev Cancels an order.
    /// @param addresses Array of trade's user, tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    function cancel(address[3] addresses, uint[4] values) external {
        OrderLibrary.Order memory order = OrderLibrary.createOrder(addresses, values);

        require(msg.sender == order.user);
        require(order.amountGive > 0 && order.amountGet > 0);

        bytes32 hash = order.hash();
        require(fills[order.user][hash] < order.amountGet);
        require(!cancelled[hash]);

        cancelled[hash] = true;
        emit Cancelled(hash);
    }

    /// @dev Creates an order which is then indexed in the orderbook.
    /// @param addresses Array of trade's tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    function order(address[2] addresses, uint[4] values) external {
        OrderLibrary.Order memory order = OrderLibrary.createOrder(
            [msg.sender, addresses[0], addresses[1]],
            values
        );

        require(vault.isApproved(order.user, this));
        require(vault.balanceOf(order.tokenGive, order.user) >= order.amountGive);
        require(order.tokenGive != order.tokenGet);
        require(order.amountGive > 0);
        require(order.amountGet > 0);

        bytes32 hash = order.hash();

        require(!orders[msg.sender][hash]);
        orders[msg.sender][hash] = true;
        
        emit Ordered(
            order.user,
            order.tokenGive,
            order.tokenGet,
            order.amountGive,
            order.amountGet,
            order.expires,
            order.nonce
        );
    }

    /// @dev Checks if a order can be traded.
    /// @param addresses Array of trade's user, tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    /// @param signature Signed order along with signature mode.
    /// @return Boolean if order can be traded
    function canTrade(address[3] addresses, uint[4] values, bytes signature)
        external
        view
        returns (bool)
    {
        OrderLibrary.Order memory order = OrderLibrary.createOrder(addresses, values);

        bytes32 hash = order.hash();

        return canTrade(order, signature, hash);
    }

    /// @dev Checks how much of an order can be filled.
    /// @param addresses Array of trade's user, tokenGive and tokenGet.
    /// @param values Array of trade's amountGive, amountGet, expires and nonce.
    /// @return Amount of the order which can be filled.
    function availableAmount(address[3] addresses, uint[4] values) external view returns (uint) {
        OrderLibrary.Order memory order = OrderLibrary.createOrder(addresses, values);
        return availableAmount(order, order.hash());
    }

    /// @dev Returns how much of an order was filled.
    /// @param user User who created the order.
    /// @param hash Hash of the order.
    /// @return Amount which was filled.
    function filled(address user, bytes32 hash) external view returns (uint) {
        return fills[user][hash];
    }

    /// @dev Sets the taker fee.
    /// @param _takerFee New taker fee.
    function setFees(uint _takerFee) public onlyOwner {
        require(_takerFee <= MAX_FEE);
        takerFee = _takerFee;
    }

    /// @dev Sets the account where fees will be transferred to.
    /// @param _feeAccount Address for the account.
    function setFeeAccount(address _feeAccount) public onlyOwner {
        require(_feeAccount != 0x0);
        feeAccount = _feeAccount;
    }

    function vault() public view returns (VaultInterface) {
        return vault;
    }

    /// @dev Checks if an order was created on chain.
    /// @param user User who created the order.
    /// @param hash Hash of the order.
    /// @return Boolean if the order was created on chain.
    function isOrdered(address user, bytes32 hash) public view returns (bool) {
        return orders[user][hash];
    }

    /// @dev Executes the actual trade by transferring balances.
    /// @param order Order to be traded.
    /// @param maxFillAmount Maximum amount of the order to be filled.
    /// @param hash Hash of the order.
    /// @return Amount that was filled.
    function performTrade(OrderLibrary.Order memory order, uint maxFillAmount, bytes32 hash) internal returns (uint) {
        uint fillAmount = SafeMath.min256(maxFillAmount, availableAmount(order, hash));

        require(vault.balanceOf(order.tokenGet, msg.sender) >= fillAmount);

        uint give = order.amountGive.mul(fillAmount).div(order.amountGet);
        uint tradeTakerFee = give.mul(takerFee).div(1 ether);

        if (tradeTakerFee > 0) {
            vault.transfer(order.tokenGive, order.user, feeAccount, tradeTakerFee);
        }

        vault.transfer(order.tokenGet, msg.sender, order.user, fillAmount);
        vault.transfer(order.tokenGive, order.user, msg.sender, give.sub(tradeTakerFee));

        fills[order.user][hash] = fills[order.user][hash].add(fillAmount);
        assert(fills[order.user][hash] <= order.amountGet);

        return fillAmount;
    }

    /// @dev Indicates whether or not an certain amount of an order can be traded.
    /// @param order Order to be traded.
    /// @param signature Signed order along with signature mode.
    /// @param hash Hash of the order.
    /// @return Boolean if order can be traded
    function canTrade(OrderLibrary.Order memory order, bytes signature, bytes32 hash)
        internal
        view
        returns (bool)
    {
        // if the order has never been traded against, we need to check the sig.
        if (fills[order.user][hash] == 0) {
            // ensures order was either created on chain, or signature is valid
            if (!isOrdered(order.user, hash) && !SignatureValidator.isValidSignature(hash, order.user, signature)) {
                return false;
            }
        }

        if (cancelled[hash]) {
            return false;
        }

        if (!vault.isApproved(order.user, this)) {
            return false;
        }

        if (order.amountGet == 0) {
            return false;
        }

        if (order.amountGive == 0) {
            return false;
        }

        // ensures that the order still has an available amount to be filled.
        if (availableAmount(order, hash) == 0) {
            return false;
        }

        return order.expires > now;
    }

    /// @dev Returns the maximum available amount that can be taken of an order.
    /// @param order Order to check.
    /// @param hash Hash of the order.
    /// @return Amount of the order that can be filled.
    function availableAmount(OrderLibrary.Order memory order, bytes32 hash) internal view returns (uint) {
        return SafeMath.min256(
            order.amountGet.sub(fills[order.user][hash]),
            vault.balanceOf(order.tokenGive, order.user).mul(order.amountGet).div(order.amountGive)
        );
    }
}