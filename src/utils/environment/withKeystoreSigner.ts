import { Accounts, EncryptedKeystoreV3Json } from 'web3-eth-accounts';

import { Environment } from './Environment';
import { withPrivateKeySigner } from './withPrivateKeySigner';

export interface WithKeystoreSignerArgs {
  keystore: EncryptedKeystoreV3Json;
  password: string;
}

const withKeystoreSigner = async (
  environment: Environment,
  { keystore, password }: WithKeystoreSignerArgs,
) => {
  const web3Accounts = new Accounts(environment.eth.currentProvider);
  const account = web3Accounts.decrypt(keystore, password);

  const enhancedEnvironment = await withPrivateKeySigner(
    environment,
    account.privateKey,
  );

  return enhancedEnvironment;
};

export { withKeystoreSigner };
