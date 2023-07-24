# Seaport Generic Adapter

The Seaport Generic Adapter is a proof of concept Seaport app that allows users to fulfill listings from other marketplaces through a Seaport interaction.  It relies on [the contract order pattern](https://github.com/ProjectOpenSea/seaport/blob/main/docs/SeaportDocumentation.md#contract-orders) that was added as part of Seaport v1.2.

## Install

To install dependencies and compile contracts:

```bash
git clone --recurse-submodules https://github.com/ProjectOpenSea/seaport-generic-adapter && cd seaport-generic-adapter && forge build
```

## Usage

```bash
forge test --fork-url $ETH_MAINNET_RPC --watch -vvv
```

## License

[MIT](LICENSE) Copyright 2023 Ozone Networks, Inc.