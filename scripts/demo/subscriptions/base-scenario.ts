/**
 * Базовый класс для сценариев тестирования подписок
 * 
 * Предоставляет общую функциональность для всех сценариев подписок:
 * - Единый интерфейс для результатов
 * - Общие утилиты для работы с подписками
 * - Стандартизированное логирование
 * - Анализ комиссий и балансов
 */

import { ethers } from "hardhat";
import { Signer, Contract } from "ethers";

// Интерфейс для результата деплоя подписок
export interface SubscriptionDeployment {
    core: Contract;
    gateway: Contract;
    subscriptionFactory: Contract;
    subscriptionManager: Contract;
    testToken: Contract;
    moduleId: string;
}

// Интерфейс для плана подписки
export interface SubscriptionPlan {
    id: string;
    name: string;
    price: bigint;
    duration: number; // в секундах
    tokenAddress: string;
    merchant: string;
}

// Интерфейс для Plan struct из контракта
export interface ContractPlan {
    chainIds: number[];
    price: bigint;
    period: number;
    token: string;
    merchant: string;
    salt: bigint;
    expiry: number;
}

// Интерфейс для результата сценария
export interface ScenarioResult {
    name: string;
    success: boolean;
    error?: string;
    details?: any;
}

// Конфигурация сценария
export interface ScenarioConfig {
    deployment: SubscriptionDeployment;
    merchant?: Signer;
    subscriber?: Signer;
}

/**
 * Базовый класс для всех сценариев подписок
 */
export abstract class BaseScenario {
    protected deployment: SubscriptionDeployment;
    protected merchant: Signer | undefined;
    protected subscriber: Signer | undefined;

    constructor(config: ScenarioConfig) {
        this.deployment = config.deployment;
        this.merchant = config.merchant;
        this.subscriber = config.subscriber;
    }

    /**
     * Получение или создание signers
     */
    protected async getSigners(): Promise<{ merchant: Signer; subscriber: Signer }> {
        if (this.merchant && this.subscriber) {
            return { merchant: this.merchant, subscriber: this.subscriber };
        }

        const signers = await ethers.getSigners();
        return {
            merchant: this.merchant || signers[1],
            subscriber: this.subscriber || signers[2]
        };
    }

    /**
     * Абстрактный метод для выполнения сценария
     */
    abstract execute(): Promise<ScenarioResult>;

    /**
     * Создание плана подписки с EIP-712 подписью
     */
    protected async createSubscriptionPlan(
        merchant: Signer,
        plan: SubscriptionPlan
    ): Promise<{ contractPlan: ContractPlan; signature: string }> {
        console.log(`📋 Создание плана подписки: ${plan.name}`);

        const network = await ethers.provider.getNetwork();
        const currentTime = Math.floor(Date.now() / 1000);

        // Создаем структуру плана для контракта
        const contractPlan: ContractPlan = {
            chainIds: [Number(network.chainId)],
            price: plan.price,
            period: plan.duration,
            token: plan.tokenAddress,
            merchant: plan.merchant,
            salt: BigInt(Math.floor(Math.random() * 1000000)),
            expiry: currentTime + (24 * 60 * 60) // Действителен 24 часа
        };

        // Создаем EIP-712 подпись - должно точно соответствовать DOMAIN_SEPARATOR в контракте
        const domain = {
            chainId: network.chainId,
            verifyingContract: await this.deployment.subscriptionManager.getAddress()
        };

        // Создаем структуру для подписи - используем оригинальную структуру Plan
        const planForSigning = {
            chainIds: contractPlan.chainIds,
            price: contractPlan.price,
            period: contractPlan.period,
            token: contractPlan.token,
            merchant: contractPlan.merchant,
            salt: contractPlan.salt,
            expiry: contractPlan.expiry
        };

        const types = {
            Plan: [
                { name: "chainIds", type: "uint256[]" }, // Используем оригинальный тип uint256[]
                { name: "price", type: "uint256" },
                { name: "period", type: "uint256" },
                { name: "token", type: "address" },
                { name: "merchant", type: "address" },
                { name: "salt", type: "uint256" },
                { name: "expiry", type: "uint64" }
            ]
        };

        const signature = await merchant.signTypedData(domain, types, planForSigning);

        console.log(`✅ План создан`);
        console.log(`  💰 Цена: ${ethers.formatEther(plan.price)} ${plan.tokenAddress === ethers.ZeroAddress ? 'ETH' : 'TOKENS'}`);
        console.log(`  ⏱️ Период: ${plan.duration} секунд`);
        console.log(`  🔗 Сеть: ${network.chainId}`);
        console.log(`  ⏰ Истекает: ${new Date(contractPlan.expiry * 1000).toLocaleString()}`);

        return { contractPlan, signature };
    }

    /**
     * Анализ балансов до и после операции
     */
    protected async analyzeBalances(
        addresses: string[],
        tokenAddress: string,
        operation: string
    ): Promise<void> {
        console.log(`\n💰 Анализ балансов ${operation}:`);

        for (const address of addresses) {
            let balance: bigint;
            let symbol: string;

            if (tokenAddress === ethers.ZeroAddress) {
                balance = await ethers.provider.getBalance(address);
                symbol = "ETH";
            } else {
                const token = await ethers.getContractAt("IERC20", tokenAddress);
                balance = await token.balanceOf(address);
                symbol = "TOKENS";
            }

            console.log(`  ${address}: ${ethers.formatEther(balance)} ${symbol}`);
        }
    }

    /**
     * Получение информации о подписке по адресу подписчика
     */
    protected async getSubscriptionInfo(subscriberAddress: string): Promise<any> {
        try {
            // Получаем информацию о подписчике
            const subscriber = await this.deployment.subscriptionManager.subscribers(subscriberAddress);

            // Проверяем, есть ли активная подписка
            if (subscriber.planHash === "0x0000000000000000000000000000000000000000000000000000000000000000") {
                return {
                    subscriber: subscriberAddress,
                    merchant: "",
                    token: "",
                    amount: 0n,
                    period: 0,
                    nextPayment: 0n,
                    nextBilling: 0n,
                    planHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
                    isActive: false
                };
            }

            // Получаем информацию о плане
            const plan = await this.deployment.subscriptionManager.plans(subscriber.planHash);

            return {
                subscriber: subscriberAddress,
                merchant: plan.merchant,
                token: plan.token,
                amount: plan.price,
                period: plan.period,
                nextPayment: subscriber.nextBilling,
                nextBilling: subscriber.nextBilling,
                planHash: subscriber.planHash,
                isActive: subscriber.planHash !== "0x0000000000000000000000000000000000000000000000000000000000000000"
            };
        } catch (error) {
            console.log(`⚠️ Не удалось получить информацию о подписке: ${error}`);
            // Возвращаем безопасный объект по умолчанию вместо null
            return {
                subscriber: subscriberAddress,
                merchant: "",
                token: "",
                amount: 0n,
                period: 0,
                nextPayment: 0n,
                nextBilling: 0n,
                planHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
                isActive: false
            };
        }
    }

    /**
     * Форматирование результата сценария
     */
    protected createResult(name: string, success: boolean, error?: string, details?: any): ScenarioResult {
        return {
            name,
            success,
            error,
            details
        };
    }
}
