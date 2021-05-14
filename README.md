# wg-client-manager
A simple script I cooked up to manage my wireguard peers.

This script does **NOT** set up Wireguard, it only manages your peers on an existing Wireguard interface. By default, it creates a "clients" directory in your current working directory and places new clients there. In order to remove a client by name, you must also call "remove" from the same directory.

## How to use
1. Clone this repository
2. Adjust `ipv4_first_valid_address` and `ipv6_first_valid_address` variables to specific configuration.
2. Adjust the template as needed.

    *NOTE: the script will replace any variables defined as ${} with environment variables. My example template leaves DNS, endpoint configuration, and allowed ip addresses as options that can be overwritten with environment variables. If you would rather not specify these variables each time, change the template.*

3. To add a client, just run:

    ```./wg-client-manager.sh add <client>```

4. To remove a client, run:

    ```./wg-client-manager.sh remove <client>```
