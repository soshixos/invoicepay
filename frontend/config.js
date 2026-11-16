// InvoicePay — configuration
// Fill CONTRACT_ADDRESS after deploying to Aevum Testnet.
// (See DEPLOYMENT.md. The frontend shows a clear "not deployed yet" state
// while the address is the zero address.)
const CONFIG = {
  chainId: 44005,
  chainIdHex: "0xabe5",
  chainName: "Aevum Testnet",
  nativeCurrency: { name: "tQDAY", symbol: "tQDAY", decimals: 18 },
  rpcUrl: "https://rpc-test.qday.info",
  explorerUrl: "https://explorer-test.qday.info",
  faucetUrl: "https://faucet.qday.info",
  tokenAddress: "0x456569838f1d43009A91ebA4263147Afd7233483",
  tokenSymbol: "tUSD8",
  tokenDecimals: 6,
  contractAddress: "0x4d60a00407d5fc38407d7bf2778d028cd4fe924c", // Deployed to Aevum Testnet 2026-11-16 (tx 0x5af89c68a3eee8ac9e6e9f0a17f33f433b8c8ec9ce89a7f1f279c2545b9647b7) — recompiled with evm_version shanghai (Aevum does not support Cancun MCOPY); supersedes 0x0DEF81dbA236181A7c590895d397A7375EBDD019
  challengeName: "Aevum Builder Challenge #1",
  challengeTrack: "Invoice Payments",
};
