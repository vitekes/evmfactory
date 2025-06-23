import { ethers } from "hardhat";

export function predictCloneAddress(impl: string, salt: string, deployer: string) {
  const prefix = "0x3d602d80600a3d3981f3363d3d373d3d3d363d73";
  const suffix = "5af43d82803e903d91602b57fd5bf3";
  const creationCode = prefix + impl.slice(2) + suffix;
  const initHash = ethers.keccak256(creationCode);
  return ethers.getCreate2Address(deployer, salt, initHash);
}

export async function deployContestFactory(priceFeedName: string = "MockPriceFeed") {
  const [deployer] = await ethers.getSigners();
  const Token = await ethers.getContractFactory("TestToken");
  const token = await Token.deploy("USD Coin", "USDC");

  const ACL = await ethers.getContractFactory("AccessControlCenter");
  const acl = await ACL.deploy();
  await acl.initialize(deployer.address);
  const FACTORY_ADMIN = ethers.keccak256(ethers.toUtf8Bytes("FACTORY_ADMIN"));
  await acl.grantRole(FACTORY_ADMIN, deployer.address);
  await acl.grantRole(await acl.FEATURE_OWNER_ROLE(), deployer.address);

  const Registry = await ethers.getContractFactory("MockRegistry");
  const registry = await Registry.deploy();
  await registry.setCoreService(
    ethers.keccak256(Buffer.from("AccessControlCenter")),
    await acl.getAddress()
  );

  const Gateway = await ethers.getContractFactory("MockPaymentGateway");
  const gateway = await Gateway.deploy();

  const PriceFeed = await ethers.getContractFactory(priceFeedName);
  const priceFeed = await PriceFeed.deploy();

  const Validator = await ethers.getContractFactory("MultiValidator");
  const validatorLogic = await Validator.deploy();

  const nextNonce = await deployer.getNonce();
  const predictedFactory = ethers.getCreateAddress({
    from: deployer.address,
    nonce: nextNonce + 2,
  });
  const moduleId = ethers.keccak256(ethers.toUtf8Bytes("Contest"));
  const salt = ethers.keccak256(
    ethers.solidityPacked(["string", "bytes32", "address"], ["Validator", moduleId, predictedFactory])
  );
  const predictedValidator = predictCloneAddress(
    await validatorLogic.getAddress(),
    salt,
    predictedFactory
  );

  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedFactory);
  await acl.grantRole(await acl.DEFAULT_ADMIN_ROLE(), predictedValidator);

  const Factory = await ethers.getContractFactory("ContestFactory");
  const factory = await Factory.deploy(
    await registry.getAddress(),
    await gateway.getAddress(),
    await validatorLogic.getAddress()
  );

  await factory.setPriceFeed(await priceFeed.getAddress());
  await factory.setUsdFeeBounds(ethers.parseEther("5"), ethers.parseEther("10"));

  return { factory, token, priceFeed, registry, gateway, acl };
}
