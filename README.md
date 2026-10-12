# maitri-cellular

A Cellular (WWAN/Mobile Data) plugin for [maitri](https://github.com/maitrios/maitri): a bar
widget with a control panel and a CLI for LTE and 5G modems, SIM cards and eSIM
profiles, APN and carrier settings, per-card data plans, text messages, and cell
diagnostics. Wi-Fi-grade ease of use for the cellular modem in the tray.

NetworkManager and ModemManager do the work of managing the modem, read over the bus;
lpac handles eSIM profiles and qmicli the deep diagnostics, each through its proxy on
the modem's own control port.

This is the maitri build of [relctx/omarchy-cellular](https://github.com/relctx/omarchy-cellular)
by relctx. It tracks upstream releases; [MAITRI.md](MAITRI.md) lists what differs. Credit for the
widget goes to relctx and its contributors.

<p align="center">
<img src="preview.png" alt="The Cellular panel at rest" width="54%"><br>
<sub>The panel: active card, connection stats, signal history, data meter, radio mode.</sub>
</p>

## 2.0.1 changes

### Features

- **The data usage section can be hidden.** A usage setting joins the Panel
  group in the settings box, or `maitri-cellular settings usage no` from the
  command line. Hiding it collapses the section and its separator.

### Fixes

- **The panel no longer refreshes because of nearby Wi-Fi.** Access points
  coming, going and changing strength were waking the widget every few seconds,
  each time running a full update. In a crowded place that cost noticeable
  battery. Cellular failover still repaints immediately.
- **The bar repaints as soon as a modem reappears.** A modem returning to the
  bus, as it does partway through a SIM switch, was taken for a routine signal
  update and ignored, leaving the bar stale until the next poll.

## 2.0 changes

For anyone coming from the 1.0.x marketplace build:

- **eSIM management without disruption.** Profile operations now use the modem's
  MBIM or QMI control port instead of AT commands. The connection stays up;
  nothing is stopped. One authorization covers a whole management session.
  This adds the `lpac-git` requirement; existing users should remove `lpac`
  and its split packages, then install `lpac-git`, which provides `libeuicc`
  itself:

  ```sh
  yay -Rns lpac            # takes libeuicc with it
  yay -Rns lpac-debug      # if present; it blocks lpac-git's debug package
  yay -S lpac-git
  ```

  Without it, eSIM management degrades to an install hint. Everything else
  works either way.
- **AT transport removed** from every automatic path. The manual `at` command
  remains for diagnostics.
- **Event-driven panel.** ModemManager and NetworkManager signals drive updates;
  polling survives only as a fallback. A SIM switch reports each stage.
- **One SIM list.** The physical card and every eSIM profile appear as tiles;
  one click switches, whatever that requires. CLI: `sims`, `use`.
- **Per-card configuration and data plans.** APN, credentials, PIN and the data
  plan move to `cellular.d/<iccid>.conf`, seeded automatically from the existing
  config the first time each card is seen. Usage is metered per card, and a
  transfer that straddles a card switch is credited to the card that used it.
- **Cell diagnostics** behind one authorization: carriers in use with widths and
  aggregation, then every cell the radio hears. CLI: `cells`, `signal`.
- **Messages**: carrier texts read, notified and deleted. CLI: `sms`.
- **Signal chart** with a selectable metric and window, and a display layout
  preset from full stats down to hidden.
- **Settings in the panel**, staged behind Save, stored in `cellular.conf`.
  CLI: `settings`. A roaming switch joins the toggle row.
- **Multi-modem support**: pick which modem the plugin drives; selection disables
  the others and moves the connection with it. CLI: `devices`, `device`.
- **Self-migration**: the first run after an update carries old settings forward,
  cleans retired state, and posts one notification.
- **Removed**: the menu-based carrier and APN pickers, replaced by the panel's
  inline browser and APN field.

## Install

```sh
maitri plugin add https://github.com/maitrios/maitri-cellular.git
maitri plugin enable maitrios.cellular --section right
```

`~/.config/maitri/cellular.conf` is created on first use.

To put the CLI on `PATH`:

```sh
ln -sf ~/.config/maitri/plugins/maitrios.cellular/bin/maitri-cellular ~/.local/bin/
```

## Requirements

A current maitri. The widget targets the Quickshell-based maitri-shell.

eSIM profile management needs lpac built with the driver matching the modem's
control port: `mbim` normally, `qmi` for modems that expose only a QMI port.
The `lpac-git` package has both, the stock `lpac` package has neither:

```sh
yay -S lpac-git
maitri pkg add zbar        # QR scan; codes can still be typed without it
```

`lpac` talks to the eUICC over the modem's control port (MBIM or QMI, matching what
the modem exposes), which ModemManager keeps open, so eSIM operations do not interrupt
the connection. `qmicli` and `mbimcli` ship with libqmi and libmbim, which
ModemManager depends on, so the diagnostics need nothing extra. `maitri-cellular doctor` reports
what is installed.

## Hardware

<img align="right" src="preview-device.png" alt="Device details" width="320">

Developed against a Lenovo ThinkPad X1 Carbon Gen 12 with a Quectel RM520N-GL (5G,
MHI/PCIe). USB modems should work, but have not been tested.

Two code paths depend on the hardware. Control-port discovery reads the captured
modem's own port list, MBIM preferred, with a `/sys/class/wwan` scan
only as the fallback while the modem object is absent. Control-port recovery after
suspend re-authorizes the USB device to force a re-probe, and returns early on PCIe,
where there is no `cdc-wdm` node.

<br clear="both">

## Panel

<img align="right" src="preview-sims.png" alt="SIM card selection" width="320">

The bar icon opens the control panel. Right-click toggles cellular, middle-click
refreshes.

The panel is event-driven: ModemManager and NetworkManager signals update it as they
happen, and a SIM switch reports each stage instead of holding one spinner.

- **Connect switch**, operator, technology, status.
- **Active identity**: which card and which APN are active.
- **Connection stats and chart**: signal metrics colored at their 3GPP thresholds,
  ping, packet loss, throughput, totals, IP. Click a value to copy it. A sparkline
  charts RSSI/RSRP, SNR, or signal quality over a chosen window.
- **Data usage**: a per-card meter. A tick marks where today falls in the billing
  period, the counting start is stamped, and the cutoff is a switch.
- **Radio mode**: auto, 5G, 4G, 3G.
- **Management chips**: device details, SIM cards, APN and carrier, cell diagnostics,
  messages. One box opens at a time. Settings sits apart on the right.

Every setting lives in `cellular.conf`, written by the panel's Settings box and
the `settings` verb alike.

<br clear="both">

### SIM cards and eSIM profiles

<img align="right" src="preview-esim.png" alt="eSIM profile management" width="320">

Every card the modem can use appears as a tile: the physical card and each eSIM
profile. One click switches; the CLI decides whether that means a slot switch, a
profile enable, or both. eSIM management lists profiles by full ICCID with rename,
delete, and install by activation code or on-screen QR scan, and shows the eUICC's
free space. Operations run over the modem's control port with the connection up, and
one authorization covers a whole management session.

```sh
maitri-cellular sims                    # every card, one per line
maitri-cellular use 8985235...          # switch to that card
maitri-cellular profile list
maitri-cellular profile enable 8985235...
maitri-cellular profile download 'LPA:1$...'
```

<br clear="both">

### Cell diagnostics

<img align="right" src="preview-diagnostics.png" alt="Cell diagnostics" width="320">

Read on demand behind one authorization, never polled. The table lists every carrier
in use (the primary and each activated secondary with its width, carrier aggregation
totaled) and then every cell the radio hears, strongest first. Neighbors are reported
for the current radio mode only.

```sh
maitri-cellular cells                   # the same table, in the terminal
maitri-cellular signal                  # every metric the modem reports
```

<br clear="both">

### Messages

<img align="right" src="preview-messages.png" alt="Messages" width="320">

Carrier texts are read, deleted, and announced as notifications when they arrive.
Balance notices, activation confirmations, and roaming warnings are most of what a
data SIM receives. The store is the modem's own memory, so it is shared by every
card in the modem.

```sh
maitri-cellular sms                     # read stored messages
maitri-cellular sms delete 3
```

<br clear="both">

### Settings

<img align="right" src="preview-settings.png" alt="Settings" width="320">

Grouped, and staged: changes apply when Save is clicked. Display holds the layout
preset (full stats, a condensed grid, a split chart-beside-stats view, chart only,
stats only, or hidden), the chart metric, and the chart period. Panel holds the
idle fallback poll, the data usage section, and SMS notifications. Network holds IP type, route metric,
and operator ID. Modem
selects which device the plugin drives on a machine with more than one. The form
reads and writes `cellular.conf`; the `settings` verb is the same interface from the
terminal.

```sh
maitri-cellular settings stats compact      # the split chart view
maitri-cellular settings spark-metric snr
maitri-cellular settings interval 120
```

<br clear="both">

## Commands

```
maitri-cellular status              modem, operator, signal, IP
maitri-cellular connect|disconnect  bring cellular up or down
maitri-cellular toggle
maitri-cellular restart             reconnect
maitri-cellular mode [auto|5g|4g|3g]
maitri-cellular sims                every card this modem can be
maitri-cellular use <iccid>         become one: slot switch, profile enable, or both
maitri-cellular sim [<n>|physical|esim]
maitri-cellular profile list        profiles on the eSIM
maitri-cellular profile enable|delete|nickname <iccid> [name]
maitri-cellular profile download <activation-code>
maitri-cellular profile scan        install from a QR code on screen
maitri-cellular carrier ...         carrier and APN selection
maitri-cellular limit ...           data cap with auto-cutoff
maitri-cellular apn <name>          set the APN
maitri-cellular apn list            APNs on the carrier's bearers
maitri-cellular pin ...             SIM lock: status, unlock, puk, on|off, change
maitri-cellular signal              every metric the modem reports, RSRQ included
maitri-cellular cells               carriers in use and every cell heard
maitri-cellular sms [delete <id>]   read or delete stored text messages
maitri-cellular devices             every modem present; * marks the one driven
maitri-cellular device <port|auto>  drive one modem, disable the rest
maitri-cellular settings <key> [value]  panel settings: stats (layout preset),
                                     spark-metric, spark-minutes, interval,
                                     sms-notify, usage, ip-type, route-metric,
                                     operator-id
maitri-cellular at '<command>'      one AT command, manual diagnostics only
maitri-cellular autoconnect on|off
maitri-cellular prefer [cellular|wifi]  which link carries traffic when both are up
maitri-cellular metered [yes|no]      whether this connection costs money
maitri-cellular roaming [yes|no]      allow data on foreign networks
maitri-cellular identify            re-read ICCID and EID
maitri-cellular apply               re-read cellular.conf and reconnect
maitri-cellular config              edit ~/.config/maitri/cellular.conf
maitri-cellular log
maitri-cellular doctor              check the setup
```


## Carrier and APN

<img align="right" src="preview-carriers.png" alt="The carrier database browser" width="320">

APNs come from `mobile-broadband-provider-info`, the database NetworkManager's own mobile
broadband wizard uses, covering 154 countries. MMS and WAP APNs are filtered out.

```sh
maitri-cellular carrier auto                  # read MCC/MNC from the SIM and apply its APN
maitri-cellular carrier list                  # countries
maitri-cellular carrier list pl               # carriers in Poland
maitri-cellular carrier list pl Orange        # that carrier's data APNs
maitri-cellular carrier set pl Orange         # apply APN, username and password
maitri-cellular apply
```

Username and password are applied for carriers that need them.

<br clear="both">

## Per-card configuration

APN, credentials, PIN, operator and the data plan belong to a card, not the machine.
They live in `~/.config/maitri/cellular.d/<iccid>.conf`, seeded from detect the first
time a card is seen and applied automatically when the active card changes.
`cellular.conf` keeps machine-wide settings. On a machine with more than
one modem, `DEVICE=` selects which one the plugin drives, by primary port
name (`wwan1mbim0`) or IMEI; unset means the first modem ModemManager
lists. Selecting a modem (`device <port>`, or the panel's picker) disables
the others through ModemManager and moves the NetworkManager profile to
the selected modem's interface; `device auto` re-enables exactly what the
plugin disabled.

## Data limit

A monthly, daily or fixed-length cap with an automatic cutoff. Prepaid bundles sold as
"N days from activation" use `days`, which rolls a window of that length forward from the
start date.

```sh
maitri-cellular limit 5G                  # cap the period at 5 GB
maitri-cellular limit day 12              # monthly package renews on the 12th
maitri-cellular limit days 30             # 30-day bundle, counted from today
maitri-cellular limit days 30 2026-08-15  # 30-day bundle bought on a past date
maitri-cellular limit period monthly|daily|days
maitri-cellular limit                     # usage, period, next reset
maitri-cellular limit reset               # zero the counter; on days, restart the period
maitri-cellular limit off                 # disable the cutoff, keep tracking usage
```

Each card runs its own meter against its own plan, accumulated from the interface byte
counters into `~/.local/state/maitri-cellular/usage.<iccid>`; a delta whose interval
straddled a card switch credits the card that was active. Counters survive reboots,
suspend and interface re-creation. At the limit, cellular disconnects with a
notification; reconnecting by hand (or `limit cutoff off`) suppresses the cutoff
until the period renews.

The meter samples on panel updates, which the event feed drives; a cutoff can overshoot
by whatever transfers between samples.

## Route metrics

Both default routes stay in the table, and the lower metric wins:

```
default via 192.168.1.1  dev wlan0    metric 600   <- traffic goes here
default via 10.0.0.1     dev wwan0    metric 700
```

Failover is immediate, because the modem holds its connection instead of dialing on
demand. `ROUTE_METRIC` sets the cellular metric, and 700 is the default.

`maitri-cellular prefer cellular` puts mobile first. The metric is computed from the routes
present at the time, so it does not assume anyone else's defaults. VPNs route by policy
rule, which the kernel evaluates ahead of the main table, and are unaffected.

## Metered

The connection is marked metered. Desktop applications read this to defer downloads and
background updates. Command-line tools ignore it.

```sh
maitri-cellular metered no      # a large plan, or just after topping up
maitri-cellular metered yes
maitri-cellular metered         # what is configured, and what NetworkManager has
```

## Permissions

Nothing is granted at install time, and normal operation does not prompt. Four
operations use `pkexec` when reached:

1. Switching SIM slots. See Notes.
2. eSIM profile operations. One authorization covers a whole management session; the
   connection stays up and nothing is stopped.
3. Cell diagnostics: one authorization reads carriers, aggregation and neighbors.
4. Recovering a control port lost across suspend, when the port is gone.

## Installed files

| Path | Contents |
| --- | --- |
| `~/.config/maitri/plugins/maitrios.cellular/` | bar widget, panel and CLI |
| `~/.config/maitri/cellular.conf` | machine-wide settings |
| `~/.config/maitri/cellular.d/` | per-card APN, PIN, data plan |
| `~/.config/maitri/shell.json` | widget entry in `bar.layout` |
| `~/.local/state/maitri-cellular/` | per-card usage meters, caches |
| `~/.local/bin/maitri-cellular` | optional symlink |

The connection is a NetworkManager `gsm` profile named `Omarchy Cellular`, overridable with
`MAITRI_CELLULAR_CONN`.

## Uninstall

```sh
maitri plugin remove maitrios.cellular
nmcli connection delete "Omarchy Cellular"
rm -f ~/.local/bin/maitri-cellular
rm -f ~/.config/maitri/cellular.conf     # machine-wide settings
rm -rf ~/.config/maitri/cellular.d       # per-card settings, including any SIM PIN
rm -rf ~/.local/state/maitri-cellular    # usage meters
```

Config and state live outside the plugin directory so they survive plugin updates
and reinstalls; that is why they are separate steps here. ModemManager and
NetworkManager are left unmodified.

## Notes

- Switching SIM slots requires root whatever polkit says. `SetPrimarySimSlot` is not on
  ModemManager's D-Bus whitelist, so the bus rejects the call before polkit sees it.
  `DBus.Error.AccessDenied` comes from the bus, and a polkit refusal names `PolicyKit`.
- An empty eSIM leaves the modem unregistered, which looks the same as poor coverage.
  `doctor` reports a config and hardware slot mismatch for this case.
- `modem.generic.bearers.value[N]` is the data bearer. `3gpp.eps.initial-bearer` comes
  first in `mmcli -K` output and has no interface.
- Use `maitri-cellular connect` instead of `nmcli connection up`. rfkill, a low power state,
  a wedged radio and a control port lost across suspend all let the modem register without
  raising a bearer, and the pre-flight clears them.
- For diagnosis, run `maitri-cellular doctor`, then `maitri-cellular log`.

## Credits

Forked from [Erruviel/omarchy-wwan](https://github.com/Erruviel/omarchy-wwan).

## License

MIT. Copyright (c) 2026 erruviel and relctx.
