import { defineConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import { configVariable } from "hardhat/config";

export default defineConfig({
  solidity: "0.8.30",
  networks: {
    somniaTestnet: {
      type: "http",
      chainType: "generic",
      url: "https://dream-rpc.somnia.network",
      chainId: 50312,
      accounts: [configVariable("0x1570b946ed2014e7beb71bf42d3290b08279fd67a69a528dfc10952bcdee897e")],
    },
  },
});