## Kalico: Mainsail does not offer updates for Kalico any more

That is the old installer. Pull this repository and run `./install.sh` again, it cleans up. See [kalico.md](kalico.md#already-installed-with-the-old-installer).

## Upgrade from the old Klipper-Toolchanger-Easy

Run the following: 

```
cd ~/klipper-toolchanger-easy
git pull
./install.sh
```
During the install you will be prompted what "type" of Z homing you want to use.  You almost certainly want option 1 here as the previous version of KTC-Easy did not support option 2.

This will create a `toolchanger` directory in `~/printer_data/configs`

- copy tools from `stealthchanger/tools` to `toolchanger/tools`
- copy any changes from `stealthchanger/toolchanger-config.cfg` into `toolchanger/toolchanger-config.cfg`


In each tool find where the partfan is assigned to the `[tool]` like:
- `fan: fan_generic Tx_partfan` and remove the `fan_generic`.  Leaving `fan: Tx_partfan`

In your `printer.cfg`, change `[include stealthchanger/toolchanger-include.cfg]` to `[include toolchanger/readonly-configs/toolchanger-include.cfg]`

If you had additional includes in your toolchanger-include.cfg those will need to move somewhere else now.

Once you have verified everything is working you can remove the `stealthchanger` folder. 