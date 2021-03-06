import { Environment } from '~/utils/environment/Environment';
import { initTestEnvironment } from '~/tests/utils/initTestEnvironment';
import { isAddress } from '~/utils/checks/isAddress';
import { deployContract } from './deployContract';
import { Contracts } from '~/Contracts';

describe('deployContract', () => {
  const shared: any = {};

  beforeAll(async () => {
    shared.env = await initTestEnvironment();
  });

  it('Happy path', async () => {
    const address = await deployContract(shared.env, Contracts.PreminedToken, [
      'TEST',
      18,
      'Test Token',
    ]);

    expect(isAddress(address)).toBe(true);
  });

  it('Throwing error if gasLimit is below gasEstimation', async () => {
    const environment: Environment = {
      ...shared.env,
      options: {
        gasLimit: '1000',
        gasPrice: shared.env.options.gasPrice,
      },
    };
    await expect(
      deployContract(environment, Contracts.MatchingMarket, [99999999999]),
    ).rejects.toThrow('gas limit:');
  });
});
