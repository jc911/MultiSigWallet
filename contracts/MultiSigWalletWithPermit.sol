//SPDX-License-Identifier: lgplv3
pragma solidity ^0.8.0;

import "./MultiSigWallet.sol";

/// @title MultiSigWalletWithPermit wallet with permit -
/// @author pagefault@126.com
contract MultiSigWalletWithPermit is MultiSigWallet {
    uint256 constant MAX =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    mapping(bytes4 => bool) internal supportedInterfaces;

    function supportsInterface(bytes4 interfaceID)
        external
        view
        returns (bool)
    {
        return supportedInterfaces[interfaceID];
    }

    function setSupportsInterface(bytes4 interfaceID, bool support)
        external
        onlyWallet
    {
        supportedInterfaces[interfaceID] = support;
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners, required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    constructor(address[] memory _owners, uint256 _required)
        MultiSigWallet(_owners, _required)
    {
        if (_required > 0) {
            setup0();
        }
    }

    function setup(address[] memory _owners, uint256 _required) public {
        initialize(_owners, _required);
        setup0();
    }

    function setup0() private {
        supportedInterfaces[0x01ffc9a7] = true;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                // keccak256(
                //     "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                // ),
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f,
                // keccak256(bytes("MultiSigWalletWithPermit")),
                0x911a814036e00323c4ca54d47b0a363338990ca044824eba7a28205763e6115a,
                // keccak256(bytes("1")),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6,
                chainId,
                address(this)
            )
        );
    }

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = 0x8d14977a529be0cde9be2de41261d56c536e10c2bfb3f797a663ac4f3676d2fe;

    /*
     * delegateCallWithPermit
     */
    /// @dev delegate call
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @param transactionId Transaction ID.
    /// @return newTransactionId Returns transaction ID.
    function delegateCallWithPermits(
        address destination,
        uint256 value,
        bytes memory data,
        uint256 transactionId,
        bytes32[] memory rs,
        bytes32[] memory ss,
        uint8[] memory vs
    ) public returns (uint256[] memory newTransactionId) {
        require(rs.length == ss.length, "invalid signs");
        require(rs.length == vs.length, "invalid signs2");
        newTransactionId = new uint256[](rs.length);
        for (uint8 i = 0; i < rs.length; ++i) {
            newTransactionId[i] = delegateCallWithPermit(
                destination,
                value,
                data,
                transactionId,
                rs[i],
                ss[i],
                vs[i]
            );
        }
    }

    /*
     * delegateCallWithPermit
     */
    /// @dev delegate call
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @param transactionId Transaction ID.
    /// @return newTransactionId Returns transaction ID.
    function delegateCallWithPermit(
        address destination,
        uint256 value,
        bytes memory data,
        uint256 transactionId,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public returns (uint256 newTransactionId) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        msg.sender,
                        destination,
                        value,
                        keccak256(data),
                        transactionId
                    )
                )
            )
        );

        address owner = ecrecover(digest, v, r, s);
        require(owner != address(0), "0 address");
        require(isOwner[owner]);

        if (destination != address(0)) {
            require(transactionId == MAX, "invalid transactionId");
            newTransactionId = addTransaction(destination, value, data);
            confirmTransactionInner(transactionId, owner);
        } else {
            confirmTransactionInner(transactionId, owner);
            newTransactionId = transactionId;
        }
    }

    function confirmTransactionInner(uint256 transactionId, address owner)
        private
        transactionExists(transactionId)
        notConfirmed(transactionId, owner)
    {
        confirmations[transactionId][owner] = true;
        emit Confirmation(owner, transactionId);
        executeTransactionInner(transactionId);
    }

    function executeTransactionInner(uint256 transactionId)
        private
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            if (
                external_call(
                    txn.destination,
                    txn.value,
                    txn.data.length,
                    txn.data
                )
            ) emit Execution(transactionId);
            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }
}
