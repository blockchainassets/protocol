import {
  transactionFactory,
  GuardFunction,
  PrepareArgsFunction,
  PostProcessFunction,
  EnhancedExecute,
} from '~/utils/solidity/transactionFactory';
import {
  QuantityInterface,
  greaterThan,
  valueIn,
  isEqual,
  toFixed,
} from '@melonproject/token-math';
import { Contracts } from '~/Contracts';
import { getHub } from '~/contracts/fund/hub/calls/getHub';
import { ensureIsNotShutDown } from '~/contracts/fund/hub/guards/ensureIsNotShutDown';
import { getRequest, RequestInvestmentResult } from '../calls/getRequest';
import { ensureAllowance } from '~/contracts/dependencies/token/guards/ensureAllowance';
import { getShareCostInAsset } from '../../accounting/calls/getShareCostInAsset';
import { getRoutes } from '../../hub/calls/getRoutes';
import { getToken } from '~/contracts/dependencies/token/calls/getToken';
import { ensure } from '~/utils/guards/ensure';

export interface RequestInvestmentArgs {
  investmentAmount: QuantityInterface;
  requestedShares: QuantityInterface;
}

const guard: GuardFunction<RequestInvestmentArgs> = async (
  environment,
  params,
  contractAddress,
) => {
  const hub = await getHub(environment, contractAddress);
  await ensureIsNotShutDown(environment, hub);
  await ensureAllowance(environment, params.investmentAmount, contractAddress);
};

const prepareArgs: PrepareArgsFunction<RequestInvestmentArgs> = async (
  environment,
  { investmentAmount, requestedShares },
  contractAddress,
) => {
  const hubAddress = await getHub(environment, contractAddress);
  const routes = await getRoutes(environment, hubAddress);
  const fundToken = await getToken(environment, routes.sharesAddress);

  const sharePriceInInvestmentAsset = await getShareCostInAsset(
    environment,
    routes.accountingAddress.toString(),
    { assetToken: investmentAmount.token, fundToken },
  );

  const priceForShares = valueIn(sharePriceInInvestmentAsset, requestedShares);

  ensure(
    greaterThan(investmentAmount, priceForShares) ||
      isEqual(investmentAmount, priceForShares),
    `Investment asset quantity provided is not enough to purchase ${toFixed(
      requestedShares,
    )} shares. Share price for ${investmentAmount.token.symbol}: ${toFixed(
      sharePriceInInvestmentAsset,
    )}`,
  );
  const requestedSharesArg = requestedShares.quantity.toString();
  const investmentAmountArg = investmentAmount.quantity.toString();
  const investmentAssetArg = investmentAmount.token.address;
  const args = [
    requestedSharesArg,
    investmentAmountArg,
    `${investmentAssetArg}`,
  ];
  return args;
};

const postProcess: PostProcessFunction<
  RequestInvestmentArgs,
  RequestInvestmentResult
> = async (environment, receipt, params, contractAddress) => {
  const request = await getRequest(environment, contractAddress, {
    of: environment.wallet.address,
  });
  return request;
};

const requestInvestment: EnhancedExecute<
  RequestInvestmentArgs,
  RequestInvestmentResult
> = transactionFactory(
  'requestInvestment',
  Contracts.Participation,
  guard,
  prepareArgs,
  postProcess,
  { amguPayable: true, incentive: true, gas: '7500000' },
);

export { requestInvestment };
