import { Environment } from '~/utils/environment/Environment';
import { WebsocketProvider } from 'web3-providers/types';

export const increaseTime = async (
  environment: Environment,
  seconds: number,
) => {
  const provider = environment.eth.currentProvider as WebsocketProvider;
  await provider.send('evm_increaseTime', [seconds as any]);
  await provider.send('evm_mine', []);
};
