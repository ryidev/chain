import { expect } from "chai";
import { ethers } from "hardhat";
import { EvotingSBT } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("EvotingSBT (Soulbound Token + Gasless Meta-Transaction)", function () {
  let evotingSBT: EvotingSBT;
  let owner: HardhatEthersSigner;
  let relayer: HardhatEthersSigner;
  let voter1: HardhatEthersSigner;
  let voter2: HardhatEthersSigner;
  let candidate1: HardhatEthersSigner;
  let candidate2: HardhatEthersSigner;
  let chainId: number;

  beforeEach(async function () {
    [owner, relayer, voter1, voter2, candidate1, candidate2] = await ethers.getSigners();

    const EvotingSBTFactory = await ethers.getContractFactory("EvotingSBT");
    evotingSBT = (await EvotingSBTFactory.deploy()) as unknown as EvotingSBT;
    await evotingSBT.waitForDeployment();

    const net = await ethers.provider.getNetwork();
    chainId = Number(net.chainId);
  });

  it("Harus berhasil deploy dengan nama dan simbol SBT yang tepat", async function () {
    expect(await evotingSBT.name()).to.equal("VoteDecen Official Voter Ballot");
    expect(await evotingSBT.symbol()).to.equal("VOTE-SBT");
    expect(await evotingSBT.owner()).to.equal(owner.address);
  });

  it("Harus bisa mendaftarkan kandidat dan mengaktifkan voting", async function () {
    await evotingSBT.tambahKandidat(candidate1.address);
    await evotingSBT.tambahKandidat(candidate2.address);

    expect(await evotingSBT.totalKandidat()).to.equal(2n);

    await evotingSBT.statusVoting(true);
    expect(await evotingSBT.sudahBisaVoting()).to.equal(true);
  });

  it("Panitia (Owner) dapat menerbitkan SBT ke pemilih, dan SBT terkunci (Soulbound)", async function () {
    const sessionId = 1;
    await expect(evotingSBT.mintBallot(voter1.address, sessionId))
      .to.emit(evotingSBT, "BallotMinted")
      .withArgs(voter1.address, 1n, sessionId)
      .and.to.emit(evotingSBT, "Locked")
      .withArgs(1n);

    const [hasTicket, tokenId, isUsed] = await evotingSBT.checkVoterTicket(voter1.address, sessionId);
    expect(hasTicket).to.be.true;
    expect(tokenId).to.equal(1n);
    expect(isUsed).to.be.false;

    expect(await evotingSBT.balanceOf(voter1.address)).to.equal(1n);
    expect(await evotingSBT.ownerOf(1n)).to.equal(voter1.address);
    expect(await evotingSBT.locked(1n)).to.be.true;

    // Pastikan tidak bisa ditransfer (Soulbound)
    await expect(
      evotingSBT.connect(voter1).transferFrom(voter1.address, voter2.address, 1n)
    ).to.be.revertedWith("SOULBOUND_TOKEN: Tiket hak suara tidak dapat dipindahtangankan!");
  });

  it("Pemilih dapat mencoblos secara Gasless (EIP-712) lewat Relayer", async function () {
    const sessionId = 1;
    await evotingSBT.tambahKandidat(candidate1.address);
    await evotingSBT.tambahKandidat(candidate2.address);
    await evotingSBT.statusVoting(true);

    // 1. Panitia minting tiket SBT ke voter1
    await evotingSBT.mintBallot(voter1.address, sessionId);

    // 2. Voter1 membuat tanda tangan EIP-712
    const contractAddress = await evotingSBT.getAddress();
    const domain = {
      name: "VoteDecenSBT",
      version: "1",
      chainId: chainId,
      verifyingContract: contractAddress,
    };

    const types = {
      VoteWithBallot: [
        { name: "candidateIndex", type: "uint256" },
        { name: "sessionId", type: "uint256" },
        { name: "voter", type: "address" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };

    const candidateIndex = 0;
    const nonce = await evotingSBT.nonces(voter1.address);
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const value = {
      candidateIndex: candidateIndex,
      sessionId: sessionId,
      voter: voter1.address,
      nonce: Number(nonce),
      deadline: deadline,
    };

    // voter1 menandatangani secara off-chain (0 gas, 0 ETH)
    const signature = await voter1.signTypedData(domain, types, value);
    const sig = ethers.Signature.from(signature);

    // 3. Relayer mengirim transaksi on-chain membayarkan gas
    await expect(
      evotingSBT.connect(relayer).voteWithBallotBySig(
        candidateIndex,
        sessionId,
        voter1.address,
        deadline,
        sig.v,
        sig.r,
        sig.s
      )
    )
      .to.emit(evotingSBT, "BallotConsumed")
      .withArgs(voter1.address, 1n, candidateIndex);

    // 4. Verifikasi suara masuk
    const kand = await evotingSBT.kandidat(0);
    expect(kand.jumlahSuara).to.equal(1n);

    // 5. Verifikasi tiket hangus (isUsed = true)
    const [, , isUsed] = await evotingSBT.checkVoterTicket(voter1.address, sessionId);
    expect(isUsed).to.be.true;
    expect(await evotingSBT.userSudahVoting(voter1.address)).to.be.true;

    // 6. Tidak bisa mencoblos kedua kali (anti double-vote)
    const newDeadline = Math.floor(Date.now() / 1000) + 3600;
    const newNonce = await evotingSBT.nonces(voter1.address);
    const value2 = {
      candidateIndex: 1,
      sessionId: sessionId,
      voter: voter1.address,
      nonce: Number(newNonce),
      deadline: newDeadline,
    };
    const signature2 = await voter1.signTypedData(domain, types, value2);
    const sig2 = ethers.Signature.from(signature2);

    await expect(
      evotingSBT.connect(relayer).voteWithBallotBySig(
        1,
        sessionId,
        voter1.address,
        newDeadline,
        sig2.v,
        sig2.r,
        sig2.s
      )
    ).to.be.revertedWith("NFT Tiket Suara Anda sudah pernah digunakan untuk mencoblos!");
  });
});
