import * as anchor from "@coral-xyz/anchor";
import { PublicKey, SystemProgram, Keypair, Transaction } from "@solana/web3.js";
import { expect } from "chai";
import nacl from "tweetnacl";
import crypto from "crypto";
import {
  createAccount,
  createMint,
  getAccount,
  getOrCreateAssociatedTokenAccount,
  mintTo,
  TOKEN_PROGRAM_ID,
  NATIVE_MINT,
} from "@solana/spl-token";

const CONFIG_SEED = Buffer.from("config");
const TREASURY_VAULT_SEED = Buffer.from("treasury_vault");
const REWARD_VAULT_SEED = Buffer.from("reward_vault");
const TOKEN_WHITELIST_SEED = Buffer.from("token_whitelist");
const LISTING_SEED = Buffer.from("listing");
const ORDER_SEED = Buffer.from("order");
const SUB_PLAN_SEED = Buffer.from("sub_plan");
const SUB_INSTANCE_SEED = Buffer.from("sub_instance");
const CONTEST_SEED = Buffer.from("contest");
const CONTEST_ENTRY_SEED = Buffer.from("contest_entry");

const SOL_LISTING_PRICE = 50_000_000; // 0.05 SOL
const SPL_LISTING_PRICE = 250_000_000; // 250 tokens (decimals=6)
const SUBSCRIPTION_PRICE = 30_000_000; // 0.03 SOL per period
const SPL_SUBSCRIPTION_PRICE = 150_000_000; // 150 tokens per period
const SUBSCRIPTION_PERIOD = 3600;
const CONTEST_PRIZE = 100_000_000; // 0.1 SOL prize pool

const FEE_BPS = 500; // 5%
const EXPECTED_SOL_FEE = Math.floor((SOL_LISTING_PRICE * FEE_BPS) / 10_000);
const EXPECTED_SPL_FEE = Math.floor((SPL_LISTING_PRICE * FEE_BPS) / 10_000);
const EXPECTED_SUB_FEE = Math.floor((SUBSCRIPTION_PRICE * FEE_BPS) / 10_000);
const EXPECTED_SPL_SUB_FEE = Math.floor((SPL_SUBSCRIPTION_PRICE * FEE_BPS) / 10_000);

describe("evmfactory program", () => {
  anchor.setProvider(anchor.AnchorProvider.local());
  const provider = anchor.getProvider() as anchor.AnchorProvider;
  const program = anchor.workspace.Evmfactory as anchor.Program<any>;
  const connection = provider.connection;
  const admin = provider.wallet as anchor.Wallet;

  const [configPda] = PublicKey.findProgramAddressSync([CONFIG_SEED], program.programId);
  const [treasuryPda] = PublicKey.findProgramAddressSync([TREASURY_VAULT_SEED], program.programId);
  const [rewardPda] = PublicKey.findProgramAddressSync([REWARD_VAULT_SEED], program.programId);
  const [whitelistPda] = PublicKey.findProgramAddressSync([TOKEN_WHITELIST_SEED], program.programId);

  before(async () => {
    await program.methods
      .initializeConfig({ feeBps: FEE_BPS })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasuryVault: treasuryPda,
        rewardVault: rewardPda,
        tokenWhitelist: whitelistPda,
        systemProgram: SystemProgram.programId,
      })
      .rpc();
  });

  const addToWhitelist = async (mint: PublicKey) => {
    await program.methods
      .updateWhitelist({ mint, add: true })
      .accounts({
        authority: admin.publicKey,
        whitelist: whitelistPda,
      })
      .rpc();
  };

  const signListingPayload = (seller: Keypair, offchainHash: Buffer): number[] => {
    const signature = nacl.sign.detached(offchainHash, seller.secretKey);
    return Array.from(signature);
  };

  const requestAirdrop = async (pubkey: PublicKey, amount: number) => {
    const sig = await connection.requestAirdrop(pubkey, amount);
    await connection.confirmTransaction(sig);
  };

  it("handles SOL listing purchase flow", async () => {
    const seller = Keypair.generate();
    const buyer = Keypair.generate();

    await Promise.all([
      requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL),
      requestAirdrop(seller.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
      requestAirdrop(buyer.publicKey, anchor.web3.LAMPORTS_PER_SOL),
    ]);

    const listingSeed = crypto.randomBytes(32);
    const offchainHash = crypto.randomBytes(32);
    const listingAddress = PublicKey.findProgramAddressSync(
      [LISTING_SEED, seller.publicKey.toBuffer(), listingSeed],
      program.programId,
    )[0];

    await program.methods
      .createListing({
        listingSeed: Array.from(listingSeed),
        offchainHash: Array.from(offchainHash),
        priceLamports: new anchor.BN(SOL_LISTING_PRICE),
        mint: NATIVE_MINT,
        sellerSignature: signListingPayload(seller, offchainHash),
      })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasury: treasuryPda,
        whitelist: whitelistPda,
        seller: seller.publicKey,
        listing: listingAddress,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    const orderPda = PublicKey.findProgramAddressSync(
      [ORDER_SEED, listingAddress.toBuffer(), buyer.publicKey.toBuffer()],
      program.programId,
    )[0];

    const treasuryBefore = await connection.getBalance(treasuryPda);

    await program.methods
      .purchaseListing({ expectedPrice: new anchor.BN(SOL_LISTING_PRICE) })
      .accounts({
        buyer: buyer.publicKey,
        listing: listingAddress,
        config: configPda,
        treasury: treasuryPda,
        order: orderPda,
        sellerDestination: seller.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .signers([buyer])
      .rpc();

    await program.methods
      .finalizeOrder()
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasury: treasuryPda,
        order: orderPda,
        buyer: buyer.publicKey,
        sellerDestination: seller.publicKey,
      })
      .rpc();

    const orderInfo = await connection.getAccountInfo(orderPda);
    expect(orderInfo).to.be.null;

    const treasuryAfter = await connection.getBalance(treasuryPda);
    expect(treasuryAfter - treasuryBefore).to.equal(EXPECTED_SOL_FEE);

    const listingState = (await program.account.listingAccount.fetch(listingAddress)) as any;
    expect(listingState.active).to.equal(false);
  });

  it("rejects listing for non-whitelisted mint", async () => {
    const seller = Keypair.generate();
    await requestAirdrop(seller.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5);

    const unlistedMint = await createMint(connection, admin.payer, admin.publicKey, null, 6);

    const listingSeed = crypto.randomBytes(32);
    const offchainHash = crypto.randomBytes(32);
    const listingAddress = PublicKey.findProgramAddressSync(
      [LISTING_SEED, seller.publicKey.toBuffer(), listingSeed],
      program.programId,
    )[0];

    let error: unknown;
    try {
      await program.methods
        .createListing({
          listingSeed: Array.from(listingSeed),
          offchainHash: Array.from(offchainHash),
          priceLamports: new anchor.BN(SPL_LISTING_PRICE),
          mint: unlistedMint,
          sellerSignature: signListingPayload(seller, offchainHash),
        })
        .accounts({
          authority: admin.publicKey,
          config: configPda,
          treasury: treasuryPda,
          whitelist: whitelistPda,
          seller: seller.publicKey,
          listing: listingAddress,
          systemProgram: SystemProgram.programId,
        })
        .rpc();
    } catch (err) {
      error = err;
    }
    expect(error).to.exist;
    const message = (error as Error).toString();
    expect(message).to.include("TokenNotWhitelisted");
  });

  it("handles SPL listing purchase flow", async () => {
    const seller = Keypair.generate();
    const buyer = Keypair.generate();

    await Promise.all([
      requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL),
      requestAirdrop(seller.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
      requestAirdrop(buyer.publicKey, anchor.web3.LAMPORTS_PER_SOL),
    ]);

    const mint = await createMint(connection, admin.payer, admin.publicKey, null, 6);
    await addToWhitelist(mint);

    const buyerAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, buyer.publicKey)
    ).address;
    const sellerAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, seller.publicKey)
    ).address;
    const treasuryAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, treasuryPda, true)
    ).address;

    await mintTo(connection, admin.payer, mint, buyerAta, admin.publicKey, 1_000_000_000);

    const listingSeed = crypto.randomBytes(32);
    const offchainHash = crypto.randomBytes(32);
    const listingAddress = PublicKey.findProgramAddressSync(
      [LISTING_SEED, seller.publicKey.toBuffer(), listingSeed],
      program.programId,
    )[0];

    await program.methods
      .createListing({
        listingSeed: Array.from(listingSeed),
        offchainHash: Array.from(offchainHash),
        priceLamports: new anchor.BN(SPL_LISTING_PRICE),
        mint,
        sellerSignature: signListingPayload(seller, offchainHash),
      })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasury: treasuryPda,
        whitelist: whitelistPda,
        seller: seller.publicKey,
        listing: listingAddress,
        systemProgram: SystemProgram.programId,
      })
      .rpc();

    const orderPda = PublicKey.findProgramAddressSync(
      [ORDER_SEED, listingAddress.toBuffer(), buyer.publicKey.toBuffer()],
      program.programId,
    )[0];

    const orderAta = await createAccount(connection, admin.payer, mint, orderPda);

    await program.methods
      .purchaseListing({ expectedPrice: new anchor.BN(SPL_LISTING_PRICE) })
      .accounts({
        buyer: buyer.publicKey,
        listing: listingAddress,
        config: configPda,
        treasury: treasuryPda,
        order: orderPda,
        sellerDestination: seller.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .remainingAccounts([
        { pubkey: mint, isWritable: false, isSigner: false },
        { pubkey: buyerAta, isWritable: true, isSigner: false },
        { pubkey: orderAta, isWritable: true, isSigner: false },
        { pubkey: sellerAta, isWritable: true, isSigner: false },
        { pubkey: treasuryAta, isWritable: true, isSigner: false },
        { pubkey: TOKEN_PROGRAM_ID, isWritable: false, isSigner: false },
      ])
      .signers([buyer])
      .rpc();

    await program.methods
      .finalizeOrder()
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasury: treasuryPda,
        order: orderPda,
        buyer: buyer.publicKey,
        sellerDestination: seller.publicKey,
      })
      .remainingAccounts([
        { pubkey: mint, isWritable: false, isSigner: false },
        { pubkey: orderAta, isWritable: true, isSigner: false },
        { pubkey: sellerAta, isWritable: true, isSigner: false },
        { pubkey: treasuryAta, isWritable: true, isSigner: false },
        { pubkey: TOKEN_PROGRAM_ID, isWritable: false, isSigner: false },
      ])
      .rpc();

    const sellerAccount = await getAccount(connection, sellerAta);
    const treasuryAccount = await getAccount(connection, treasuryAta);

    expect(Number(sellerAccount.amount)).to.equal(SPL_LISTING_PRICE - EXPECTED_SPL_FEE);
    expect(Number(treasuryAccount.amount)).to.equal(EXPECTED_SPL_FEE);

    const orderInfo = await connection.getAccountInfo(orderPda);
    expect(orderInfo).to.be.null;
  });

  it("processes SOL subscription payments", async () => {
    const creator = Keypair.generate();
    const subscriber = Keypair.generate();

    await Promise.all([
      requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL),
      requestAirdrop(creator.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
      requestAirdrop(subscriber.publicKey, anchor.web3.LAMPORTS_PER_SOL),
    ]);

    const planSeed = crypto.randomBytes(32);
    const planAddress = PublicKey.findProgramAddressSync(
      [SUB_PLAN_SEED, creator.publicKey.toBuffer(), planSeed],
      program.programId,
    )[0];

    await program.methods
      .configureSubscription({
        planSeed: Array.from(planSeed),
        offchainHash: Array.from(crypto.randomBytes(32)),
        pricePerPeriod: new anchor.BN(SUBSCRIPTION_PRICE),
        periodSeconds: new anchor.BN(SUBSCRIPTION_PERIOD),
        mint: NATIVE_MINT,
      })
      .accounts({
        creator: creator.publicKey,
        config: configPda,
        whitelist: whitelistPda,
        plan: planAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([creator])
      .rpc();

    const instanceSeed = crypto.randomBytes(32);
    const instanceAddress = PublicKey.findProgramAddressSync(
      [SUB_INSTANCE_SEED, subscriber.publicKey.toBuffer(), instanceSeed],
      program.programId,
    )[0];

    const treasuryBefore = await connection.getBalance(treasuryPda);
    const creatorBefore = await connection.getBalance(creator.publicKey);

    const now = Math.floor(Date.now() / 1000);
    await program.methods
      .processSubscriptionPayment({
        instanceSeed: Array.from(instanceSeed),
        nowTs: new anchor.BN(now),
      })
      .accounts({
        subscriber: subscriber.publicKey,
        config: configPda,
        treasury: treasuryPda,
        plan: planAddress,
        creatorDestination: creator.publicKey,
        instance: instanceAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([subscriber])
      .rpc();

    const next = now + SUBSCRIPTION_PERIOD;
    await program.methods
      .processSubscriptionPayment({
        instanceSeed: Array.from(instanceSeed),
        nowTs: new anchor.BN(next),
      })
      .accounts({
        subscriber: subscriber.publicKey,
        config: configPda,
        treasury: treasuryPda,
        plan: planAddress,
        creatorDestination: creator.publicKey,
        instance: instanceAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([subscriber])
      .rpc();

    const treasuryAfter = await connection.getBalance(treasuryPda);
    const creatorAfter = await connection.getBalance(creator.publicKey);

    expect(treasuryAfter - treasuryBefore).to.equal(EXPECTED_SUB_FEE * 2);
    expect(creatorAfter - creatorBefore).to.equal((SUBSCRIPTION_PRICE - EXPECTED_SUB_FEE) * 2);

    const instanceState = (await program.account.subscriptionInstanceAccount.fetch(instanceAddress)) as any;
    expect(Number(instanceState.lastPaymentAt)).to.equal(next);
  });

  it("processes SPL subscription payments", async () => {
    const creator = Keypair.generate();
    const subscriber = Keypair.generate();

    await Promise.all([
      requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL),
      requestAirdrop(creator.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
      requestAirdrop(subscriber.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
    ]);

    const mint = await createMint(connection, admin.payer, admin.publicKey, null, 6);
    await addToWhitelist(mint);

    const subscriberAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, subscriber.publicKey)
    ).address;
    const creatorAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, creator.publicKey)
    ).address;
    const treasuryAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, treasuryPda, true)
    ).address;

    await mintTo(connection, admin.payer, mint, subscriberAta, admin.publicKey, 1_000_000_000);

    const planSeed = crypto.randomBytes(32);
    const planAddress = PublicKey.findProgramAddressSync(
      [SUB_PLAN_SEED, creator.publicKey.toBuffer(), planSeed],
      program.programId,
    )[0];

    await program.methods
      .configureSubscription({
        planSeed: Array.from(planSeed),
        offchainHash: Array.from(crypto.randomBytes(32)),
        pricePerPeriod: new anchor.BN(SPL_SUBSCRIPTION_PRICE),
        periodSeconds: new anchor.BN(SUBSCRIPTION_PERIOD),
        mint,
      })
      .accounts({
        creator: creator.publicKey,
        config: configPda,
        whitelist: whitelistPda,
        plan: planAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([creator])
      .rpc();

    const instanceSeed = crypto.randomBytes(32);
    const instanceAddress = PublicKey.findProgramAddressSync(
      [SUB_INSTANCE_SEED, subscriber.publicKey.toBuffer(), instanceSeed],
      program.programId,
    )[0];

    const treasuryBefore = await getAccount(connection, treasuryAta);
    const creatorBefore = await getAccount(connection, creatorAta);

    const now = Math.floor(Date.now() / 1000);
    await program.methods
      .processSubscriptionPayment({
        instanceSeed: Array.from(instanceSeed),
        nowTs: new anchor.BN(now),
      })
      .accounts({
        subscriber: subscriber.publicKey,
        config: configPda,
        treasury: treasuryPda,
        plan: planAddress,
        creatorDestination: creator.publicKey,
        instance: instanceAddress,
        systemProgram: SystemProgram.programId,
      })
      .remainingAccounts([
        { pubkey: subscriberAta, isWritable: true, isSigner: false },
        { pubkey: creatorAta, isWritable: true, isSigner: false },
        { pubkey: treasuryAta, isWritable: true, isSigner: false },
        { pubkey: TOKEN_PROGRAM_ID, isWritable: false, isSigner: false },
      ])
      .signers([subscriber])
      .rpc();

    const next = now + SUBSCRIPTION_PERIOD;
    await program.methods
      .processSubscriptionPayment({
        instanceSeed: Array.from(instanceSeed),
        nowTs: new anchor.BN(next),
      })
      .accounts({
        subscriber: subscriber.publicKey,
        config: configPda,
        treasury: treasuryPda,
        plan: planAddress,
        creatorDestination: creator.publicKey,
        instance: instanceAddress,
        systemProgram: SystemProgram.programId,
      })
      .remainingAccounts([
        { pubkey: subscriberAta, isWritable: true, isSigner: false },
        { pubkey: creatorAta, isWritable: true, isSigner: false },
        { pubkey: treasuryAta, isWritable: true, isSigner: false },
        { pubkey: TOKEN_PROGRAM_ID, isWritable: false, isSigner: false },
      ])
      .signers([subscriber])
      .rpc();

    const treasuryAfter = await getAccount(connection, treasuryAta);
    const creatorAfter = await getAccount(connection, creatorAta);

    expect(Number(treasuryAfter.amount) - Number(treasuryBefore.amount)).to.equal(
      EXPECTED_SPL_SUB_FEE * 2,
    );
    expect(Number(creatorAfter.amount) - Number(creatorBefore.amount)).to.equal(
      (SPL_SUBSCRIPTION_PRICE - EXPECTED_SPL_SUB_FEE) * 2,
    );

    const instanceState = (await program.account.subscriptionInstanceAccount.fetch(instanceAddress)) as any;
    expect(Number(instanceState.lastPaymentAt)).to.equal(next);
  });

  it("allows admin to withdraw treasury SOL and SPL", async () => {
    const recipient = Keypair.generate();
    await requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL);
    await requestAirdrop(recipient.publicKey, anchor.web3.LAMPORTS_PER_SOL / 10);

    const solDeposit = 10_000_000;
    const solWithdraw = 5_000_000;

    const fundTx = new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: admin.publicKey,
        toPubkey: treasuryPda,
        lamports: solDeposit,
      }),
    );
    await provider.sendAndConfirm(fundTx);

    const recipientBefore = await connection.getBalance(recipient.publicKey);
    await program.methods
      .withdrawTreasuryNative({ amount: new anchor.BN(solWithdraw) })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasuryVault: treasuryPda,
        destination: recipient.publicKey,
      })
      .rpc();

    const recipientAfter = await connection.getBalance(recipient.publicKey);
    expect(recipientAfter - recipientBefore).to.equal(solWithdraw);

    const mint = await createMint(connection, admin.payer, admin.publicKey, null, 6);
    await addToWhitelist(mint);

    const treasuryAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, treasuryPda, true)
    ).address;
    const recipientAta = (
      await getOrCreateAssociatedTokenAccount(connection, admin.payer, mint, recipient.publicKey)
    ).address;

    const splDeposit = 400_000_000;
    const splWithdraw = 150_000_000;

    await mintTo(connection, admin.payer, mint, treasuryAta, admin.publicKey, splDeposit);

    const recipientTokenBefore = await getAccount(connection, recipientAta);
    await program.methods
      .withdrawTreasurySpl({ amount: new anchor.BN(splWithdraw) })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        treasuryVault: treasuryPda,
        mint,
        treasuryTokenAccount: treasuryAta,
        destinationTokenAccount: recipientAta,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .rpc();

    const recipientTokenAfter = await getAccount(connection, recipientAta);
    expect(Number(recipientTokenAfter.amount) - Number(recipientTokenBefore.amount)).to.equal(splWithdraw);
  });

  it("runs contest lifecycle", async () => {
    const creator = Keypair.generate();
    const contestant = Keypair.generate();

    await Promise.all([
      requestAirdrop(admin.publicKey, anchor.web3.LAMPORTS_PER_SOL),
      requestAirdrop(creator.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
      requestAirdrop(contestant.publicKey, anchor.web3.LAMPORTS_PER_SOL / 5),
    ]);

    const fundTx = new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: admin.publicKey,
        toPubkey: rewardPda,
        lamports: CONTEST_PRIZE,
      }),
    );
    await provider.sendAndConfirm(fundTx);

    const contestSeed = crypto.randomBytes(32);
    const contestAddress = PublicKey.findProgramAddressSync(
      [CONTEST_SEED, creator.publicKey.toBuffer(), contestSeed],
      program.programId,
    )[0];

    const deadline = Math.floor(Date.now() / 1000) + 2;

    await program.methods
      .createContest({
        contestSeed: Array.from(contestSeed),
        offchainHash: Array.from(crypto.randomBytes(32)),
        deadline: new anchor.BN(deadline),
        prizeLamports: new anchor.BN(CONTEST_PRIZE),
      })
      .accounts({
        creator: creator.publicKey,
        config: configPda,
        rewardVault: rewardPda,
        contest: contestAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([creator])
      .rpc();

    const entrySeed = crypto.randomBytes(32);
    const entryAddress = PublicKey.findProgramAddressSync(
      [CONTEST_ENTRY_SEED, contestAddress.toBuffer(), entrySeed],
      program.programId,
    )[0];

    await program.methods
      .submitContestEntry({
        contestSeed: Array.from(contestSeed),
        entrySeed: Array.from(entrySeed),
        offchainHash: Array.from(crypto.randomBytes(32)),
      })
      .accounts({
        contestant: contestant.publicKey,
        contest: contestAddress,
        entry: entryAddress,
        systemProgram: SystemProgram.programId,
      })
      .signers([contestant])
      .rpc();

    await new Promise((resolve) => setTimeout(resolve, 3_000));

    const winnerBalanceBefore = await connection.getBalance(contestant.publicKey);

    await program.methods
      .resolveContest({
        contestSeed: Array.from(contestSeed),
        entrySeed: Array.from(entrySeed),
        winner: contestant.publicKey,
        score: new anchor.BN(100),
      })
      .accounts({
        authority: admin.publicKey,
        config: configPda,
        rewardVault: rewardPda,
        contest: contestAddress,
        entry: entryAddress,
        rewardDestination: contestant.publicKey,
      })
      .rpc();

    const winnerBalanceAfter = await connection.getBalance(contestant.publicKey);
    expect(winnerBalanceAfter - winnerBalanceBefore).to.equal(CONTEST_PRIZE);

    const contestInfo = await connection.getAccountInfo(contestAddress);
    expect(contestInfo).to.be.null;

    const entryState = (await program.account.contestEntryAccount.fetch(entryAddress)) as any;
    expect(Number(entryState.score)).to.equal(100);
  });
});
