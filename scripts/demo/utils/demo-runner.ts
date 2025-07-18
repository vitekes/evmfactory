/**
 * Общий утилитарный класс для запуска демонстраций
 * Устраняет дублирование кода между различными демо-скриптами
 */

import { ethers } from "hardhat";
import { Signer } from "ethers";

export interface ScenarioResult {
    name: string;
    success: boolean;
    error?: string;
    details?: {
        gasUsed?: string | number | bigint;
        gatewayEarned?: string | number | bigint;
        [key: string]: any;
    };
}

export interface DemoConfig {
    title: string;
    signerRoles: string[];
    contractsSection: string;
    scenariosSection: string;
    successMessage: string;
    contractPaths: string;
    testPaths: string;
    scenarioPaths: string;
    individualScenarios: string[];
}

export interface DeploymentResult {
    // Основные контракты
    core: any;
    registry: any;
    tokenFilter: any;
    feeProcessor: any;
    orchestrator: any;
    gateway: any;
    marketplace: any;
    moduleId: string;

    // Тестовые токены
    testToken: any;

    // Контракты системы конкурсов
    contestFactory: any;
    contestValidator: any;
    feeManager: any;
    tokenValidator: any;

    // Адреса для удобства
    addresses: {
        core: string;
        registry: string;
        tokenFilter: string;
        feeProcessor: string;
        orchestrator: string;
        gateway: string;
        marketplace: string;
        testToken: string;
        contestFactory: string;
        contestValidator: string;
        feeManager: string;
        tokenValidator: string;
    };

    // Дополнительные свойства для расширяемости
    [key: string]: any;
}

export class DemoRunner {
    private config: DemoConfig;
    private signers: Signer[] = [];
    private network: any;
    private startTime: number = 0;

    constructor(config: DemoConfig) {
        this.config = config;
    }

    /**
     * Запуск полной демонстрации
     */
    async run(
        deployFunction: () => Promise<DeploymentResult>,
        scenariosFunction: (deployment: DeploymentResult) => Promise<ScenarioResult[]>
    ): Promise<void> {
        this.startTime = Date.now();

        this.printHeader();

        try {
            await this.initializeNetwork();
            await this.displayNetworkInfo();
            await this.checkBalances();

            const deployment = await this.runDeployment(deployFunction);
            const results = await this.runScenarios(scenariosFunction, deployment);

            this.displayFinalStatistics(results);
            this.displayAdditionalInfo();
            this.printFooter();

        } catch (error: any) {
            this.handleError(error);
        }
    }

    private printHeader(): void {
        console.log(`🎬 ${this.config.title}`);
        console.log("=".repeat(80));
        console.log("📅 Время запуска:", new Date().toLocaleString());
    }

    private async initializeNetwork(): Promise<void> {
        this.signers = await ethers.getSigners();
        this.network = await ethers.provider.getNetwork();
        console.log("🌐 Сеть:", this.network.name || "неизвестно");
    }

    private async displayNetworkInfo(): Promise<void> {
        console.log("\n🔧 ИНФОРМАЦИЯ О СЕТИ И АККАУНТАХ:");
        console.log("-".repeat(50));
        console.log("🌐 Сеть:", this.network.name, `(Chain ID: ${this.network.chainId})`);

        for (let i = 0; i < Math.min(this.signers.length, this.config.signerRoles.length); i++) {
            const roleIcon = this.getRoleIcon(this.config.signerRoles[i]);
            console.log(`${roleIcon} ${this.config.signerRoles[i]}:`, await this.signers[i].getAddress());
        }
    }

    private getRoleIcon(role: string): string {
        const icons: { [key: string]: string } = {
            'Деплоер': '👤',
            'Продавец': '🏪',
            'Покупатель': '👥',
            'Организатор': '🏆',
            'Участник 1': '👥',
            'Участник 2': '👥',
            'Мерчант': '🏪',
            'Подписчик': '👥'
        };
        return icons[role] || '👤';
    }

    private async checkBalances(): Promise<void> {
        console.log("\n💰 НАЧАЛЬНЫЕ БАЛАНСЫ:");
        console.log("-".repeat(50));

        const balances: bigint[] = [];
        for (let i = 0; i < Math.min(this.signers.length, this.config.signerRoles.length); i++) {
            const balance = await ethers.provider.getBalance(this.signers[i].address);
            balances.push(balance);
            const roleIcon = this.getRoleIcon(this.config.signerRoles[i]);
            console.log(`${roleIcon} ${this.config.signerRoles[i]}:`, ethers.formatEther(balance), "ETH");
        }

        // Проверяем минимальные балансы
        const minBalance = ethers.parseEther("1.0");
        const lowBalances = balances.some(balance => balance < minBalance);

        if (lowBalances) {
            console.log("\n⚠️ ПРЕДУПРЕЖДЕНИЕ: Низкие балансы!");
            console.log("   Рекомендуется иметь минимум 1 ETH на каждом аккаунте");
            console.log("   Для локальной сети используйте: npx hardhat node");
        }
    }

    private async runDeployment(deployFunction: () => Promise<DeploymentResult>): Promise<DeploymentResult> {
        console.log(`\n📦 ${this.config.contractsSection}:`);
        console.log("=".repeat(80));

        const startDeployTime = Date.now();
        const deployment = await deployFunction();
        const deployTime = Date.now() - startDeployTime;

        console.log("\n✅ ДЕПЛОЙ ЗАВЕРШЕН УСПЕШНО!");
        console.log("-".repeat(50));
        console.log("⏱️ Время деплоя:", deployTime, "ms");

        // Отображаем основные контракты
        if (deployment.core) {
            console.log("📋 Core System:", await deployment.core.getAddress());
        }
        if (deployment.gateway) {
            console.log("🚪 Payment Gateway:", await deployment.gateway.getAddress());
        }
        if (deployment.testToken) {
            console.log("🪙 Test Token:", await deployment.testToken.getAddress());
        }

        // Отображаем дополнительные контракты
        for (const [key, contract] of Object.entries(deployment)) {
            if (key !== 'core' && key !== 'gateway' && key !== 'testToken' && key !== 'moduleId') {
                if (contract && typeof contract.getAddress === 'function') {
                    console.log(`📋 ${key}:`, await contract.getAddress());
                } else if (typeof contract === 'string' && key === 'moduleId') {
                    console.log(`🆔 Module ID:`, contract);
                }
            }
        }

        return deployment;
    }

    private async runScenarios(
        scenariosFunction: (deployment: DeploymentResult) => Promise<ScenarioResult[]>,
        deployment: DeploymentResult
    ): Promise<ScenarioResult[]> {
        console.log(`\n🎯 ${this.config.scenariosSection}:`);
        console.log("=".repeat(80));

        const startScenariosTime = Date.now();
        const results = await scenariosFunction(deployment);
        const scenariosTime = Date.now() - startScenariosTime;

        return results;
    }

    private displayFinalStatistics(results: ScenarioResult[]): void {
        console.log("\n📈 ФИНАЛЬНАЯ СТАТИСТИКА:");
        console.log("=".repeat(80));

        const successCount = results.filter(r => r.success).length;
        const failureCount = results.length - successCount;
        const scenariosTime = Date.now() - this.startTime;

        console.log("📊 Общие результаты:");
        console.log(`  ✅ Успешных сценариев: ${successCount}/${results.length}`);
        console.log(`  ❌ Неудачных сценариев: ${failureCount}/${results.length}`);
        console.log(`  📊 Процент успеха: ${Math.round((successCount / results.length) * 100)}%`);
        console.log(`  ⏱️ Общее время выполнения: ${scenariosTime}ms`);
        console.log(`  ⚡ Среднее время на сценарий: ${Math.round(scenariosTime / results.length)}ms`);

        // Детальная статистика по газу
        this.displayGasStatistics(results, successCount);

        // Отображаем результат
        if (successCount === results.length) {
            console.log("\n🎉 ВСЕ СЦЕНАРИИ ВЫПОЛНЕНЫ УСПЕШНО!");
            console.log(`✨ ${this.config.successMessage}`);
            console.log("🚀 Готова к использованию в продакшене");
        } else {
            console.log("\n⚠️ НЕКОТОРЫЕ СЦЕНАРИИ ЗАВЕРШИЛИСЬ С ОШИБКАМИ");
            console.log("🔍 Проверьте логи выше для получения деталей");

            const failedScenarios = results.filter(r => !r.success);
            console.log("\n❌ Неудачные сценарии:");
            failedScenarios.forEach((scenario, index) => {
                console.log(`  ${index + 1}. ${scenario.name}: ${scenario.error}`);
            });
        }
    }

    private displayGasStatistics(results: ScenarioResult[], successCount: number): void {
        let totalGasUsed = 0n;
        let totalFeesCollected = 0n;

        results.forEach(result => {
            if (result.success && result.details?.gasUsed) {
                try {
                    const gasUsed = typeof result.details.gasUsed === 'string' 
                        ? result.details.gasUsed 
                        : result.details.gasUsed.toString();
                    totalGasUsed += BigInt(gasUsed);
                } catch (e) {
                    // Ignore parsing errors for gas usage
                }
            }
            if (result.success && result.details?.gatewayEarned) {
                try {
                    totalFeesCollected += BigInt(result.details.gatewayEarned);
                } catch (e) {
                    // Ignore parsing errors for fee collection
                }
            }
        });

        if (totalGasUsed > 0n) {
            console.log(`  ⛽ Общий расход газа: ${totalGasUsed.toString()}`);
            if (successCount > 0) {
                console.log(`  💰 Средний расход газа: ${(totalGasUsed / BigInt(successCount)).toString()}`);
            }
        }

        if (totalFeesCollected > 0n) {
            console.log(`  🏛️ Общие комиссии собраны: ${ethers.formatEther(totalFeesCollected)} ETH`);
        }
    }

    private displayAdditionalInfo(): void {
        console.log("\n📋 Доступные сценарии для индивидуального запуска:");
        this.config.individualScenarios.forEach(scenario => {
            console.log(`  • ${scenario}`);
        });

        console.log("\n📚 ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ:");
        console.log("-".repeat(50));
        console.log("📖 Документация: README.md");
        console.log("🔧 Конфигурация: hardhat.config.ts");
        console.log(`📁 Контракты: ${this.config.contractPaths}`);
        console.log(`🧪 Тесты: ${this.config.testPaths}`);
        console.log(`📋 Сценарии: ${this.config.scenarioPaths}`);
    }

    private printFooter(): void {
        console.log("\n🏁 ДЕМОНСТРАЦИЯ ЗАВЕРШЕНА");
        console.log("=".repeat(80));
        console.log("📅 Время завершения:", new Date().toLocaleString());
        console.log("⏱️ Общее время выполнения:", Date.now() - this.startTime, "ms");
    }

    private handleError(error: any): void {
        console.log("\n❌ КРИТИЧЕСКАЯ ОШИБКА В ДЕМОНСТРАЦИИ:");
        console.log("=".repeat(80));
        console.log("🚨 Ошибка:", error.message);

        if (error.stack) {
            console.log("\n📋 Stack trace:");
            console.log(error.stack);
        }

        console.log("\n🔧 ВОЗМОЖНЫЕ РЕШЕНИЯ:");
        console.log("-".repeat(50));
        console.log("1. Убедитесь, что локальная сеть запущена: npx hardhat node");
        console.log("2. Проверьте баланс аккаунтов");
        console.log("3. Убедитесь, что все зависимости установлены: npm install");
        console.log("4. Проверьте конфигурацию сети в hardhat.config.ts");
        console.log("5. Очистите кеш: npx hardhat clean");

        process.exit(1);
    }
}
