#!/data/data/com.termux/files/usr/bin/bash
# Monad Testnet Mint Detector Auto-Installer
# Works on Android Termux

echo "=== Monad Testnet Mint Detector Auto-Installer ==="

# Update & install dependencies
pkg update -y
pkg upgrade -y
pkg install -y nodejs-lts git

# Create project folder
mkdir -p monad-mint-detector
cd monad-mint-detector

# Create package.json
cat > package.json << 'EOF'
{
  "name": "monad-mint-detector",
  "version": "1.0.0",
  "main": "mintDetector.js",
  "type": "module",
  "dependencies": {
    "ethers": "^6.10.0",
    "express": "^4.18.2",
    "axios": "^1.6.8"
  }
}
EOF

# Install dependencies
npm install

# Create config.json
cat > config.json << 'EOF'
{
  "DISCORD_WEBHOOK": "",
  "RPC": "https://testnet-rpc.monad.xyz",
  "PORT": 3000
}
EOF

# Create the mint detector script
cat > mintDetector.js << 'EOF'
import { ethers } from "ethers";
import express from "express";
import axios from "axios";
import fs from "fs";

// ----------------------
// Load config
// ----------------------
const config = JSON.parse(fs.readFileSync("config.json"));
const { DISCORD_WEBHOOK, RPC, PORT } = config;

const provider = new ethers.JsonRpcProvider(RPC);

const ZERO = "0x0000000000000000000000000000000000000000";
const ERC721_TRANSFER = ethers.id("Transfer(address,address,uint256)");
const ERC1155_SINGLE = ethers.id("TransferSingle(address,address,address,uint256,uint256)");
const ERC1155_BATCH = ethers.id("TransferBatch(address,address,address,uint256[],uint256[])");

let recent = [];

// Discord alert
async function alertDiscord(msg) {
  if (!DISCORD_WEBHOOK) return;
  try {
    await axios.post(DISCORD_WEBHOOK, { content: msg });
  } catch (e) {
    console.log("Discord webhook error:", e);
  }
}

// Log mint
function record(event) {
  recent.unshift(event);
  if (recent.length > 100) recent.pop();
  fs.appendFileSync("mints.log", JSON.stringify(event) + "\n");
}

// Parse mint logs
function handleMint(contract, tokenId, to, block, type) {
  const event = { contract, tokenId, to, block, type };
  console.log("MINT:", event);

  const msg = `🚨 **LIVE MINT**  
**Contract:** \`${contract}\`
**Token ID:** \`${tokenId}\`
**To:** \`${to}\`
**Type:** \`${type}\`
**Block:** \`${block}\``;

  alertDiscord(msg);
  record(event);
}

// Detect mints
async function start() {
  console.log("🔥 Listening for mint events on Monad Testnet (10143)...");

  provider.on("block", async (num) => {
    const block = await provider.getBlockWithTransactions(num);

    for (const tx of block.transactions) {
      const receipt = await provider.getTransactionReceipt(tx.hash);
      if (!receipt) continue;

      for (const log of receipt.logs) {
        const address = log.address;
        const topic0 = log.topics[0];

        // ERC721
        if (topic0 === ERC721_TRANSFER) {
          const from = "0x" + log.topics[1].slice(26);
          const to = "0x" + log.topics[2].slice(26);
          const tokenId = BigInt(log.topics[3]).toString();

          if (from.toLowerCase() === ZERO.toLowerCase()) {
            handleMint(address, tokenId, to, num, "ERC721");
          }
        }

        // ERC1155 single
        if (topic0 === ERC1155_SINGLE) {
          const from = "0x" + log.topics[2].slice(26);
          const to = "0x" + log.topics[3].slice(26);

          if (from.toLowerCase() === ZERO.toLowerCase()) {
            const abi = ethers.AbiCoder.defaultAbiCoder();
            const [id] = abi.decode(["uint256", "uint256"], log.data);
            handleMint(address, id.toString(), to, num, "ERC1155 Single");
          }
        }

        // ERC1155 batch
        if (topic0 === ERC1155_BATCH) {
          const from = "0x" + log.topics[2].slice(26);
          const to = "0x" + log.topics[3].slice(26);

          if (from.toLowerCase() === ZERO.toLowerCase()) {
            const abi = ethers.AbiCoder.defaultAbiCoder();
            const [ids] = abi.decode(["uint256[]", "uint256[]"], log.data);

            ids.forEach((id) => {
              handleMint(address, id.toString(), to, num, "ERC1155 Batch");
            });
          }
        }
      }
    }
  });
}

// Dashboard
const app = express();
app.get("/", (req, res) => {
  res.json(recent);
});

start();
app.listen(PORT, () => console.log("Dashboard live on port", PORT));
EOF

echo "=== INSTALL COMPLETE ==="
echo ""
echo "Next steps:"
echo "1. Edit config.json and add your Discord webhook"
echo "2. Run the detector:"
echo "   node mintDetector.js"
