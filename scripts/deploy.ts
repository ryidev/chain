const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const { ethers } = hre;
  
  console.log("Menyiapkan deployment EvotingSBT...");
  const EvotingSBT = await ethers.getContractFactory("EvotingSBT");
  
  console.log("Mendeploy kontrak EvotingSBT (Soulbound Token + Gasless Meta-Transaction)...");
  const evoting = await EvotingSBT.deploy();

  await evoting.waitForDeployment();

  const address = await evoting.getAddress();
  console.log("✅ Kontrak EvotingSBT berhasil di-deploy!");
  console.log("📍 Alamat Kontrak:", address);

  // Ambil artifact ABI
  const artifactPath = path.join(__dirname, "../artifacts/contracts/EvotingSBT.sol/EvotingSBT.json");
  if (fs.existsSync(artifactPath)) {
    const artifact = JSON.parse(fs.readFileSync(artifactPath, "utf8"));
    const abiJson = JSON.stringify(artifact.abi, null, 2);

    // 1. Update fe/lib/evotingContract.ts
    const feContractFile = path.join(__dirname, "../../fe/lib/evotingContract.ts");
    const feContent = `import { ethers } from 'ethers';

// ALAMAT KONTRAK RESMI EVOTING SBT
export const CONTRACT_ADDRESS = '${address}';

// EIP-712 DOMAIN & TYPES UNTUK GASLESS META-TRANSACTION (0 ETH)
export const EIP712_DOMAIN = (contractAddress: string, chainId: number) => ({
  name: "VoteDecenSBT",
  version: "1",
  chainId: chainId,
  verifyingContract: contractAddress,
});

export const EIP712_TYPES = {
  VoteWithBallot: [
    { name: "candidateIndex", type: "uint256" },
    { name: "sessionId", type: "uint256" },
    { name: "voter", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
};

export const CONTRACT_ABI = ${abiJson} as const;

export const getEvotingContract = async () => {
  if (typeof window !== 'undefined' && (window as any).ethereum) {
    const provider = new ethers.BrowserProvider((window as any).ethereum);
    const signer = await provider.getSigner();
    return new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
  }
  throw new Error("MetaMask tidak terdeteksi");
};
`;
    fs.writeFileSync(feContractFile, feContent, "utf8");
    console.log("📁 Berhasil memperbarui fe/lib/evotingContract.ts");

    // 2. Update mobile/lib/evotingContract.ts
    const mobileContractFile = path.join(__dirname, "../../mobile/lib/evotingContract.ts");
    const mobileContent = `// ALAMAT KONTRAK & ABI EVOTING SBT (Sinkron otomatis dari hardhat deploy)
export const CONTRACT_ADDRESS = (process.env.EXPO_PUBLIC_CONTRACT_ADDRESS ||
  '${address}') as \`0x\${string}\`;

export const EIP712_DOMAIN = (contractAddress: string, chainId: number) => ({
  name: "VoteDecenSBT",
  version: "1",
  chainId: chainId,
  verifyingContract: contractAddress,
});

export const EIP712_TYPES = {
  VoteWithBallot: [
    { name: "candidateIndex", type: "uint256" },
    { name: "sessionId", type: "uint256" },
    { name: "voter", type: "address" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

export const CONTRACT_ABI = ${abiJson} as const;
`;
    fs.writeFileSync(mobileContractFile, mobileContent, "utf8");
    console.log("📁 Berhasil memperbarui mobile/lib/evotingContract.ts");

    // 3. Update mobile/.env
    const mobileEnvFile = path.join(__dirname, "../../mobile/.env");
    if (fs.existsSync(mobileEnvFile)) {
      let mobileEnv = fs.readFileSync(mobileEnvFile, "utf8");
      mobileEnv = mobileEnv.replace(
        /EXPO_PUBLIC_CONTRACT_ADDRESS=.*/,
        `EXPO_PUBLIC_CONTRACT_ADDRESS=${address}`
      );
      if (!mobileEnv.includes("EXPO_PUBLIC_API_URL")) {
        mobileEnv += `\n# Next.js Backend URL (untuk gasless relay & SBT minting dari mobile)\nEXPO_PUBLIC_API_URL=http://127.0.0.1:3000\n`;
      }
      fs.writeFileSync(mobileEnvFile, mobileEnv, "utf8");
      console.log("📁 Berhasil memperbarui mobile/.env");
    }
  }
}

main().catch((error) => {
  console.error("Terjadi kesalahan saat deploy:");
  console.error(error);
  process.exitCode = 1;
});
