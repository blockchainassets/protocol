#!/usr/bin/env node
// require('babel-polyfill');
const R = require('ramda');
const path = require('path');
const fs = require('fs');
const program = require('commander');
const pkg = require('../package.json');
const { getPrice } = require('@melonproject/token-math/price');
const { createQuantity } = require('@melonproject/token-math/quantity');

program
  .version(pkg.version, '-v, --version')
  .description('The Melon Protocol CLI');

program
  .command('compile [<glob>]')
  .description('Compile the Melon Smart Contracts.')
  .action(async glob => {
    console.log(glob ? `Compiling ${glob}` : 'Compiling all contracts' );

    try {
      const { compileGlob } = require('./compile');
      // await initTestEnvironment();
      await compileGlob(glob);
    } catch (e) {
      console.error(e);
    } finally {
      process.exit();
    }
  });

program
  .command('deploy <endpoint>')
  .description('Deploy the Melon smart contracts')
  .action(async (endpoint) => {
    console.error('Deployment is currently not implemented. Tests now run on the in-memory devchain.');

    process.exit();
  });

program
  .command('set-price <symbol> <value>')
  .description('Sets a price on the price feed.')
  .action(async (symbol, value) => {
    console.log(`Setting the price for ${symbol} to ${value}`);
    const {
      initTestEnvironment,
    } = require('../lib/utils/environment/initTestEnvironment');
    const { update } = require('../lib/contracts/prices/transactions/update');
    const { getQuoteToken } = require('../lib/contracts/prices/calls/getQuoteToken');
    const environment = await initTestEnvironment();
    const quoteToken = await getQuoteToken(environment, environment.deployment.priceSource);
    const baseToken = tokens.find((token) => {
      return token.symbol === symbol.toUpperCase();
    });

    const newPrice = getPrice(
      createQuantity(baseToken, 1),
      createQuantity(quoteToken, value),
    );

    await update(environment, environemnt.deployment.priceSource, [newPrice]);

    console.log(`Successfully updated the price for ${symbol}.`);
    process.exit();
  });

program.on('command:*', function() {
  program.help();
  process.exit();
});

if (process.argv.length < 3) {
  program.help();
  process.exit();
}

program.parse(process.argv);
