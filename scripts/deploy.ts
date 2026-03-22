import { createWalletClient, createPublicClient, http, defineChain } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import * as dotenv from "dotenv";
import fs from "fs";

dotenv.config();

// ─── Define Somnia Testnet ──────────────────────────────────────
const somniaTestnet = defineChain({
  id: 50312,
  name: "Somnia Testnet",
  nativeCurrency: { name: "STT", symbol: "STT", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://dream-rpc.somnia.network"] },
  },
});

async function main() {
  console.log("🚀 Deploying ChainPulse to Somnia Testnet...\n");

  // ─── Setup wallet ───────────────────────────────────────────────
  const privateKey = process.env.PRIVATE_KEY as `0x${string}`;
  if (!privateKey) throw new Error("PRIVATE_KEY not found in .env");

  const account = privateKeyToAccount(privateKey);

  const publicClient = createPublicClient({
    chain: somniaTestnet,
    transport: http(),
  });

  const walletClient = createWalletClient({
    account,
    chain: somniaTestnet,
    transport: http(),
  });

  console.log(`🔑 Deploying from wallet: ${account.address}\n`);

  // ─── Load artifacts ─────────────────────────────────────────────
  const registryArtifact = JSON.parse(
    fs.readFileSync("./artifacts/contracts/StrategyRegistry.sol/StrategyRegistry.json", "utf8")
  );
  const whaleGuardArtifact = JSON.parse(
    fs.readFileSync("./artifacts/contracts/WhaleGuard.sol/WhaleGuard.json", "utf8")
  );
  const liquidationArtifact = JSON.parse(
    fs.readFileSync("./artifacts/contracts/LiquidationShield.sol/LiquidationShield.json", "utf8")
  );
  const dipBuyerArtifact = JSON.parse(
    fs.readFileSync("./artifacts/contracts/DipBuyer.sol/DipBuyer.json", "utf8")
  );

  // ─── Deploy StrategyRegistry ────────────────────────────────────
  console.log("📋 Deploying StrategyRegistry...");
  const registryHash = await walletClient.deployContract({
    abi: registryArtifact.abi,
    bytecode: registryArtifact.bytecode,
    args: [],
  });
  console.log(`   Tx sent: ${registryHash}`);
  const registryReceipt = await publicClient.waitForTransactionReceipt({ hash: registryHash });
  const registryAddress = registryReceipt.contractAddress!;
  console.log(`✅ StrategyRegistry deployed at: ${registryAddress}\n`);

  // ─── Deploy WhaleGuard ──────────────────────────────────────────
  console.log("🐋 Deploying WhaleGuard...");
  const whaleThreshold = BigInt("1000000000000000000000");
  const whaleHash = await walletClient.deployContract({
    abi: whaleGuardArtifact.abi,
    bytecode: whaleGuardArtifact.bytecode,
    args: [registryAddress, 1n, whaleThreshold],
  });
  console.log(`   Tx sent: ${whaleHash}`);
  const whaleReceipt = await publicClient.waitForTransactionReceipt({ hash: whaleHash });
  const whaleGuardAddress = whaleReceipt.contractAddress!;
  console.log(`✅ WhaleGuard deployed at: ${whaleGuardAddress}\n`);

  // Publish as Strategy #1
  const publishWhaleHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "publishStrategy",
    args: [
      "WhaleGuard",
      "Detects large whale transfers on-chain and activates protection automatically. No bot. No server. Powered by Somnia Reactivity.",
      "Whale",
      whaleGuardAddress,
    ],
  });
  await publicClient.waitForTransactionReceipt({ hash: publishWhaleHash });
  console.log(`✅ WhaleGuard published as Strategy #1`);

  const seedWhaleHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "seedExecutionData",
    args: [1n, 47n, 45n],
  });
  await publicClient.waitForTransactionReceipt({ hash: seedWhaleHash });
  console.log(`✅ Seeded: 47 executions, 45 successes\n`);

  // ─── Deploy LiquidationShield ───────────────────────────────────
  console.log("🛡️ Deploying LiquidationShield...");
  const liquidationHash = await walletClient.deployContract({
    abi: liquidationArtifact.abi,
    bytecode: liquidationArtifact.bytecode,
    args: [registryAddress, 2n],
  });
  console.log(`   Tx sent: ${liquidationHash}`);
  const liquidationReceipt = await publicClient.waitForTransactionReceipt({ hash: liquidationHash });
  const liquidationShieldAddress = liquidationReceipt.contractAddress!;
  console.log(`✅ LiquidationShield deployed at: ${liquidationShieldAddress}\n`);

  // Publish as Strategy #2
  const publishLiqHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "publishStrategy",
    args: [
      "LiquidationShield",
      "Monitors on-chain liquidation events and activates protection automatically for subscribed users. No bot. No server.",
      "DeFi",
      liquidationShieldAddress,
    ],
  });
  await publicClient.waitForTransactionReceipt({ hash: publishLiqHash });
  console.log(`✅ LiquidationShield published as Strategy #2`);

  const seedLiqHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "seedExecutionData",
    args: [2n, 31n, 29n],
  });
  await publicClient.waitForTransactionReceipt({ hash: seedLiqHash });
  console.log(`✅ Seeded: 31 executions, 29 successes\n`);

  // ─── Deploy DipBuyer ────────────────────────────────────────────
  console.log("📉 Deploying DipBuyer...");
  const dipHash = await walletClient.deployContract({
    abi: dipBuyerArtifact.abi,
    bytecode: dipBuyerArtifact.bytecode,
    args: [registryAddress, 3n, 5n],
  });
  console.log(`   Tx sent: ${dipHash}`);
  const dipReceipt = await publicClient.waitForTransactionReceipt({ hash: dipHash });
  const dipBuyerAddress = dipReceipt.contractAddress!;
  console.log(`✅ DipBuyer deployed at: ${dipBuyerAddress}\n`);

  // Publish as Strategy #3
  const publishDipHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "publishStrategy",
    args: [
      "DipBuyer",
      "Detects on-chain price drops above 5% and executes a buy automatically. Never miss a dip again. No bot. No server.",
      "Price",
      dipBuyerAddress,
    ],
  });
  await publicClient.waitForTransactionReceipt({ hash: publishDipHash });
  console.log(`✅ DipBuyer published as Strategy #3`);

  const seedDipHash = await walletClient.writeContract({
    address: registryAddress,
    abi: registryArtifact.abi,
    functionName: "seedExecutionData",
    args: [3n, 22n, 21n],
  });
  await publicClient.waitForTransactionReceipt({ hash: seedDipHash });
  console.log(`✅ Seeded: 22 executions, 21 successes\n`);

  // ─── Summary ────────────────────────────────────────────────────
  console.log("═══════════════════════════════════════");
  console.log("🎉 ChainPulse Deployment Complete!");
  console.log("═══════════════════════════════════════");
  console.log(`StrategyRegistry  : ${registryAddress}`);
  console.log(`WhaleGuard        : ${whaleGuardAddress}`);
  console.log(`LiquidationShield : ${liquidationShieldAddress}`);
  console.log(`DipBuyer          : ${dipBuyerAddress}`);
  console.log("═══════════════════════════════════════");
  console.log("\n⚠️  Save these addresses for the frontend!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});