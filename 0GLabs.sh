#!/bin/bash

# Print information about the setup and ask for user confirmation
echo "$(tput setaf 6)════════════════════════════════════════════════════════════"
echo "$(tput setaf 6)║       Welcome to 0G Labs Node Setup Script!                  ║"
echo "$(tput setaf 6)║                                                              ║"
echo "$(tput setaf 6)║     Follow us on Twitter:                                   ║"
echo "$(tput setaf 6)║     https://twitter.com/cipher_airdrop                      ║"
echo "$(tput setaf 6)║                                                              ║"
echo "$(tput setaf 6)║     Join us on Telegram:                                    ║"
echo "$(tput setaf 6)║     - https://t.me/+tFmYJSANTD81MzE1                       ║"
echo "$(tput setaf 6)╚════════════════════════════════════════════════════════════$(tput sgr0)"

read -p "Do you want to continue with the installation? (Y/N): " answer
if [[ $answer != "Y" && $answer != "y" ]]; then
    echo "Aborting installation."
    exit 1
fi

# Rest of the installation script...

# Update and upgrade system packages
sudo apt update && sudo apt upgrade -y

# Install necessary packages
sudo apt install curl git wget htop tmux build-essential liblz4-tool jq make lz4 gcc unzip -y

# Set Go version
ver="1.22.2"

# Download and install Go
wget "https://golang.org/dl/go$ver.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$ver.linux-amd64.tar.gz"
rm "go$ver.linux-amd64.tar.gz"
echo "export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin" >> $HOME/.bash_profile
source $HOME/.bash_profile

# Clone the project repository
cd $HOME
git clone https://github.com/0glabs/0g-evmos.git
cd 0g-evmos

# Checkout specific version
git checkout v1.0.0-testnet

# Build the binaries
make build

# Create necessary directory structure
mkdir -p $HOME/.evmosd/cosmovisor/genesis/bin

# Move compiled binary to directory
mv build/evmosd $HOME/.evmosd/cosmovisor/genesis/bin/

# Clean up build directory
rm -rf build

# Link Genesis to Current Directory
sudo ln -s $HOME/.evmosd/cosmovisor/genesis $HOME/.evmosd/cosmovisor/current -f

# Link Binary to System Path
sudo ln -s $HOME/.evmosd/cosmovisor/current/bin/evmosd /usr/local/bin/evmosd -f

# Install cosmovisor
go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest

# Create and configure systemd service
sudo tee /etc/systemd/system/evmosd.service > /dev/null << EOF
[Unit]
Description=evmosd node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which cosmovisor) run start
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
Environment="DAEMON_HOME=$HOME/.evmosd"
Environment="DAEMON_NAME=evmosd"
Environment="UNSAFE_SKIP_BACKUP=true"
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:$HOME/.evmosd/cosmovisor/current/bin"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable evmosd.service

# Set chain ID, configure keyring backend, and node endpoint
evmosd config chain-id zgtendermint_9000-1
evmosd config keyring-backend os
evmosd config node tcp://localhost:16457

# Initialize node with user-provided name
echo "Enter your node name:"
read node_name
evmosd init $node_name --chain-id zgtendermint_9000-1

# Download genesis file
curl -Ls https://github.com/0glabs/0g-evmos/releases/download/v1.0.0-testnet/genesis.json > $HOME/.evmosd/config/genesis.json

# Set peers and seeds in config
PEERS="1248487ea585730cdf5d3c32e0c2a43ad0cda973@peer-zero-gravity-testnet.trusted-point.com:26326"
SEEDS="8c01665f88896bca44e8902a30e4278bed08033f@54.241.167.190:26656,b288e8b37f4b0dbd9a03e8ce926cd9c801aacf27@54.176.175.48:26656,8e20e8e88d504e67c7a3a58c2ea31d965aa2a890@54.193.250.204:26656,e50ac888b35175bfd4f999697bdeb5b7b52bfc06@54.215.187.94:26656"

sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.evmosd/config/config.toml

# Set minimum gas prices
sed -i "s/^minimum-gas-prices *=.*/minimum-gas-prices = \"0.00252aevmos\"/" $HOME/.evmosd/config/app.toml

# Modify config.toml and app.toml ports
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:16458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:16457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:16460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:16456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":16466\"%" $HOME/.evmosd/config/config.toml
sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:16417\"%; s%^address = \":8080\"%address = \":16480\"%; s%^address = \"0.0.0.0:9090\"%address = \"0.0.0.0:16490\"%; s%^address = \"0.0.0.0:9091\"%address = \"0.0.0.0:16491\"%; s%:8545%:16445%; s%:8546%:16446%; s%:6065%:16465%" $HOME/.evmosd/config/app.toml

# Stop evmosd service
sudo systemctl stop evmosd

# Backup validator state
cp $HOME/.evmosd/data/priv_validator_state.json $HOME/.evmosd/priv_validator_state.json.backup

# Clear blockchain data except address book
evmosd tendermint unsafe-reset-all --home $HOME/.evmosd --keep-addr-book

# Download and extract blockchain state snapshot
curl -L http://37.120.189.81/0g_testnet/0g_snap.tar.lz4 | tar -I lz4 -xf - -C $HOME/.evmosd

# Restore validator state
mv $HOME/.evmosd/priv_validator_state.json.backup $HOME/.evmosd/data/priv_validator_state.json

# Restart evmosd service
sudo systemctl daemon-reload
sudo systemctl restart evmosd
