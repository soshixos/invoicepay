// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InvoicePayments} from "../src/InvoicePayments.sol";
import {MockToken} from "../src/MockToken.sol";

/// @notice Deploy InvoicePayments.
///         - Aevum Testnet: uses the live tUSD8 token (0x456569838f1d43009A91ebA4263147Afd7233483).
///           Run: forge script script/Deploy.s.sol --rpc-url https://rpc-test.qday.info
///                --private-key <key> --broadcast
///         - Local (Anvil): deploys a MockToken first and uses it as the
///           settlement token. Run: anvil & forge script script/Deploy.s.sol
///           --rpc-url http://127.0.0.1:8545 --broadcast
///           Set DEPLOY_MOCK_TOKEN=1 to force the mock on any network.
contract Deploy is Script {
    address public constant TUSD8 = 0x456569838f1d43009A91ebA4263147Afd7233483;
    uint256 public constant AEVUM_CHAIN_ID = 44005;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address token = TUSD8;
        bool useMock = vm.envOr("DEPLOY_MOCK_TOKEN", false);

        if (block.chainid != AEVUM_CHAIN_ID || useMock) {
            vm.startBroadcast(deployerKey);
            MockToken mock = new MockToken("tUSD8", "tUSD8", 6);
            token = address(mock);
            console.log("MockToken deployed at:", token);
        } else {
            vm.startBroadcast(deployerKey);
        }

        InvoicePayments inv = new InvoicePayments(token);
        vm.stopBroadcast();

        console.log("InvoicePayments deployed at:", address(inv));
        console.log("Settlement token:", token);
        console.log("Chain id:", block.chainid);
        console.log("Deployer:", vm.addr(deployerKey));
    }
}
