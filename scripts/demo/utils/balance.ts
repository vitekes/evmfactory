import {ethers} from "hardhat";
import {Contract, Signer} from "ethers";

// Mock token cache no longer needed since we use real ERC20 contracts

/**
 * Получение баланса аккаунта (нативный токен или ERC20)
 */
export async function getBalance(address: string, token: string): Promise<bigint> {
    if (token === ethers.ZeroAddress) {
        return await ethers.provider.getBalance(address);
    }

    const tokenContract = await ethers.getContractAt("IERC20", token);
    return await tokenContract.balanceOf(address);
}

/**
 * Получение баланса в удобочитаемом формате
 */
export async function getFormattedBalance(address: string, token: string, symbol: string = "ETH"): Promise<string> {
    const balance = await getBalance(address, token);
    return `${ethers.formatEther(balance)} ${symbol}`;
}

/**
 * Структура для хранения информации о балансах
 */
export interface BalanceInfo {
    address: string;
    nativeBalance: bigint;
    tokenBalances: Map<string, bigint>;
}

/**
 * Получение полной информации о балансах аккаунта
 */
export async function getAccountBalances(
    address: string,
    tokens: string[] = []
): Promise<BalanceInfo> {
    console.log(`💰 Получение балансов для ${address}...`);

    const nativeBalance = await ethers.provider.getBalance(address);
    const tokenBalances = new Map<string, bigint>();

    for (const tokenAddress of tokens) {
        if (tokenAddress !== ethers.ZeroAddress) {
            try {
                const balance = await getBalance(address, tokenAddress);
                tokenBalances.set(tokenAddress, balance);
            } catch (error) {
                console.log(`⚠️ Ошибка получения баланса токена ${tokenAddress}:`, error);
                tokenBalances.set(tokenAddress, 0n);
            }
        }
    }

    return {
        address,
        nativeBalance,
        tokenBalances
    };
}

/**
 * Получение полной информации о балансах для множества аккаунтов
 */
export async function getMultipleAccountBalances(
    addresses: string[],
    tokens: string[] = []
): Promise<BalanceInfo[]> {
    console.log(`💰 Получение балансов для ${addresses.join(',')}...`);

    const balances: BalanceInfo[] = [];

    for (const address of addresses) {
        const balance = await getAccountBalances(address, tokens);
        balances.push(balance);
    }

    return balances;
}

/**
 * Отображение балансов в консоли
 */
export async function displayBalances(
    balanceInfo: BalanceInfo,
    tokenSymbols: Map<string, string> = new Map()
): Promise<void> {
    console.log(`💳 Балансы для ${balanceInfo.address}:`);
    console.log(`  Native ETH: ${ethers.formatEther(balanceInfo.nativeBalance)} ETH`);

    for (const [tokenAddress, balance] of balanceInfo.tokenBalances) {
        const symbol = tokenSymbols.get(tokenAddress) || "TOKEN";
        console.log(`  ${symbol}: ${ethers.formatEther(balance)} ${symbol}`);
    }
}

/**
 * Отображение балансов для множества аккаунтов в консоли
 */
export async function displayMultipleBalances(
    balanceInfos: BalanceInfo[],
    tokenSymbols: Map<string, string> = new Map()
): Promise<void> {
    for (const balanceInfo of balanceInfos) {
        await displayBalances(balanceInfo, tokenSymbols);
    }
}

/**
 * Сравнение балансов до и после операции
 */
export interface BalanceChange {
    address: string;
    nativeChange: bigint;
    tokenChanges: Map<string, bigint>;
}

export function calculateBalanceChanges(
    before: BalanceInfo,
    after: BalanceInfo
): BalanceChange {
    const nativeChange = after.nativeBalance - before.nativeBalance;
    const tokenChanges = new Map<string, bigint>();

    // Проверяем изменения в токенах
    for (const [tokenAddress, afterBalance] of after.tokenBalances) {
        const beforeBalance = before.tokenBalances.get(tokenAddress) || 0n;
        const change = afterBalance - beforeBalance;
        tokenChanges.set(tokenAddress, change);
    }

    // Проверяем токены, которые были в before, но нет в after
    for (const [tokenAddress, beforeBalance] of before.tokenBalances) {
        if (!after.tokenBalances.has(tokenAddress)) {
            tokenChanges.set(tokenAddress, -beforeBalance);
        }
    }

    return {
        address: before.address,
        nativeChange,
        tokenChanges
    };
}

/**
 * Сравнение балансов для множества аккаунтов
 */
export function calculateMultipleBalanceChanges(
    before: BalanceInfo[],
    after: BalanceInfo[]
): BalanceChange[] {
    const changes: BalanceChange[] = [];

    for (let i = 0; i < before.length && i < after.length; i++) {
        const change = calculateBalanceChanges(before[i], after[i]);
        changes.push(change);
    }

    return changes;
}

/**
 * Отображение изменений балансов
 */
export function displayBalanceChanges(
    changes: BalanceChange,
    tokenSymbols: Map<string, string> = new Map()
): void {
    console.log(`📊 Изменения балансов для ${changes.address}:`);

    const nativeChangeStr = changes.nativeChange >= 0 ? "+" : "";
    console.log(`  Native ETH: ${nativeChangeStr}${ethers.formatEther(changes.nativeChange)} ETH`);

    for (const [tokenAddress, change] of changes.tokenChanges) {
        const symbol = tokenSymbols.get(tokenAddress) || "TOKEN";
        const changeStr = change >= 0 ? "+" : "";
        console.log(`  ${symbol}: ${changeStr}${ethers.formatEther(change)} ${symbol}`);
    }
}

/**
 * Отображение изменений балансов для множества аккаунтов
 */
export function displayMultipleBalanceChanges(
    changes: BalanceChange[],
    tokenSymbols: Map<string, string> = new Map()
): void {
    for (const change of changes) {
        displayBalanceChanges(change, tokenSymbols);
    }
}

/**
 * Минт токенов для тестирования
 */
export async function mintTokens(
  token: Contract,
  recipient: string,
  amount: bigint
): Promise<void> {
  console.log(`🪙 Минт ${ethers.formatEther(amount)} токенов для ${recipient}...`);

  try {
    const tx = await token.mint(recipient, amount);

    // Проверяем, есть ли метод wait (для совместимости с mock токенами)
    if (tx && typeof tx.wait === 'function') {
      await tx.wait();
    }

    console.log("✅ Токены заминчены");
  } catch (error) {
    console.log("⚠️ Ошибка минта токенов:", error);
    throw error;
  }
}

/**
 * Подготовка токенов для тестирования (минт и approve)
 */
export async function prepareTokensForTesting(
  token: Contract,
  user: Signer,
  spender: string,
  amount: bigint
): Promise<void> {
  const userAddress = await user.getAddress();

  // Минтим токены пользователю
  await mintTokens(token, userAddress, amount);

  // Даем approve spender'у
  console.log(`✅ Выдача approve на ${ethers.formatEther(amount)} токенов...`);
  const erc20Token = await ethers.getContractAt("IERC20", await token.getAddress());
  const tx = await erc20Token.connect(user).approve(spender, amount);

  // Проверяем, есть ли метод wait (для совместимости с mock токенами)
  if (tx && typeof tx.wait === 'function') {
    await tx.wait();
  }

  console.log("✅ Approve выдан");
}

/**
 * Проверка комиссий в транзакции
 */
export interface FeeInfo {
    totalFee: bigint;
    platformFee: bigint;
    processingFee: bigint;
    recipient: string;
}

/**
 * Анализ комиссий из события транзакции
 */
export async function analyzeFees(
    receipt: any,
    marketplace: Contract
): Promise<FeeInfo[]> {
    console.log("🔍 Анализ комиссий в транзакции...");

    const fees: FeeInfo[] = [];

    if (!receipt || !receipt.logs) {
        console.log("⚠️ Нет логов в транзакции");
        return fees;
    }

    // Ищем события связанные с комиссиями
    for (const log of receipt.logs) {
        try {
            const parsedLog = marketplace.interface.parseLog(log);

            if (parsedLog && parsedLog.name === "FeePaid") {
                // Предполагаем, что есть событие FeePaid
                fees.push({
                    totalFee: parsedLog.args.amount,
                    platformFee: parsedLog.args.platformFee || 0n,
                    processingFee: parsedLog.args.processingFee || 0n,
                    recipient: parsedLog.args.recipient
                });
            }
        } catch (error) {
            // Игнорируем ошибки парсинга логов от других контрактов
        }
    }

    if (fees.length === 0) {
        console.log("ℹ️ Комиссии не найдены в транзакции");
    } else {
        console.log(`✅ Найдено ${fees.length} комиссий`);
        fees.forEach((fee, index) => {
            console.log(`  Комиссия ${index + 1}:`);
            console.log(`    Общая сумма: ${ethers.formatEther(fee.totalFee)} ETH`);
            console.log(`    Получатель: ${fee.recipient}`);
        });
    }

    return fees;
}

/**
 * Проверка достаточности баланса для операции
 */
export async function checkSufficientBalance(
    user: string,
    token: string,
    requiredAmount: bigint
): Promise<boolean> {
    const balance = await getBalance(user, token);
    const sufficient = balance >= requiredAmount;

    const tokenName = token === ethers.ZeroAddress ? "Native ETH" : token;
    console.log(`💰 Проверка баланса ${tokenName}:`);
    console.log(`  Текущий: ${ethers.formatEther(balance)}`);
    console.log(`  Требуется: ${ethers.formatEther(requiredAmount)}`);
    console.log(`  Достаточно: ${sufficient ? "✅ Да" : "❌ Нет"}`);

    return sufficient;
}

/**
 * Получение цены газа для транзакции
 */
export async function getGasPrice(): Promise<bigint> {
    const feeData = await ethers.provider.getFeeData();
    return feeData.gasPrice || 0n;
}

/**
 * Оценка стоимости газа для транзакции
 */
export async function estimateTransactionCost(
    contract: Contract,
    methodName: string,
    args: any[]
): Promise<bigint> {
    try {
        const gasEstimate = await contract[methodName].estimateGas(...args);
        const gasPrice = await getGasPrice();
        return gasEstimate * gasPrice;
    } catch (error) {
        console.log("⚠️ Ошибка оценки газа:", error);
        return 0n;
    }
}
