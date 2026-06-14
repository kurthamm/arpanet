# Kurt's fork documentation

This branch documents and supports two related but separate work streams:

- Hosted ARPANET terminal operation: see [docs/hosted-terminal-fixes.md](docs/hosted-terminal-fixes.md).
- Safe hosted ITS host lifecycle commands: see [docs/host-lifecycle.md](docs/host-lifecycle.md).
- Stanford/SU-AI PARRY restoration: see [docs/host11-parry-restoration.md](docs/host11-parry-restoration.md).
- DigitalOcean migration and runtime hardening: see [docs/digitalocean-migration.md](docs/digitalocean-migration.md).
- Physical PiDP-10 external host integration: see [kurthamm/pidp10-arpanet-node](https://github.com/kurthamm/pidp10-arpanet-node).

## Hosted Terminal Quick Use

From the hosted terminal page:

```text
@L 6
@L 134
@L 70
@L 126
@L 198
@L 11
@L 41
```

Host `1` / octal `001` is UCLA-NMC's historically correct address at IMP #1.
The live implementation is a real SIMH Sigma 7 running CP-V F00 media from the
public Sigma CP-V kit. It is not the recovered UCLA SEX system; original
UCLA-NMC/SEX storage is still not present in this repository.

Host `11` / octal `013` is Stanford/SU-AI WAITS. The live packs include the
restored PARRY support files required for the 1972 scenario 19 experience.

Host `41` / octal `051` is an optional external PiDP-10 path. In this DigitalOcean deployment, the browser launcher maps `@L 41` and `@L 051` to the PiDP SIMH MTY terminal over Tailscale. ARPANET reachability for host `41` is validated separately through the IMP62/IMP41 link with `NCP=ncp31 ./ncp-ping -c1 41`.

Host `6` / octal `006` is MIT-MULTICS at IMP #6 host index 0. The live
implementation uses DPS8M with public MR12.8 media and a visitor account; it is
not recovered 1972 MIT H645 `Multics 17.6b` storage.

Hosted ITS hosts `70`, `126`, `134`, and `198` are local PDP-10 simulators on the droplet.
Host `126` / octal `176` is HILTON-KA1, the Washington Hilton conference-site
KA host at IMP #62 host index 1. It is separate from MIT-ML, which is host
`198` / octal `306` at IMP #6 host index 3.
Their browser sessions use localhost-only simulator terminal lines so the public
terminal remains usable even when a vintage ITS image does not accept ARPANET
TELNET from the browser source NCP.

## Hosted ITS Host Operations

For safe status, restart, and verification of hosted ITS hosts `70`, `126`, `134`, and `198`, use:

```sh
mini/hostctl.sh status all
mini/hostctl.sh verify all
mini/hostctl.sh restart 70
```

Before changing runtime state, run:

```sh
mini/arpanet-health.sh
```

`mini/hostctl.sh` stops simulator process groups, waits for ports to clear, restores clean packs, and verifies NCP reachability. Do not restart these hosts with raw `screen` commands.

## Repository Split

The PiDP-10 work is intentionally kept in a separate companion repository because it documents home-lab replica hardware, IMP41 bridging, and overlay networking. Site-specific PiDP-10/Tailscale configuration should stay out of this repository unless it becomes a generic upstream-supported scenario.

---
# arpanet

WORK IN PROGRESS - Very early unless you are involved.

See the project in action (if we have the server up...) at https://obsolescence.dev/arpanet_home.html or run the setup on your own computer.

# Surf the Arpanet like it's 1972 again
This is the entry page for a faithful recreation of the Arpanet circa 1972-73, connecting replicas of the historical computers, running their recovered historical software, and talking to each other again over replica IMP routers - also running their original firmware. Explore the Arpanet and details of its nodes through the interactive chart below. Or read on to get a live terminal into the early 70s.
<br><br>
<b>This is work in progress! We hope to recover and reconstruct more and more Arpanet nodes over the coming months and years. Which is why, for now, this page is not published yet.</b>

<p align="center">
  <img width="45%" src="https://github.com/user-attachments/assets/0f15e12c-32c7-4e11-b749-cbcfac2c8092" />
  <img width="3%" src="https://github.com/user-attachments/assets/b12f9d23-c9e4-487f-8ea7-6813e5e96848" />
  <img width="45%" src="https://github.com/user-attachments/assets/61b43e18-ead0-488d-a556-a800fffb78d9" />
</p>
<br>
<img width="1916" height="960" alt="image" src="https://github.com/user-attachments/assets/5b03c509-ea3f-4941-a594-f89f749821bc" />
<br><br>
Arpanet. At first, not many people cared. The break-through came at the 1972 ICCC convention, known as the 'Arpanet Ball'. Attendees could get online, and were given a booklet with 'scenarios' to try for themselves.
No exaggeration - at the Arpanet Ball, the consequences of 'networking' suddenly became clear. 
<br><br>
So, it is interesting (actually, historically important!) to find out what exactly people saw at the event. Attendees could log themselves in on clunky Teletypes or very basic CRT terminals; they then could connect to the various computers on Arpanet and 'do things'. What things? That is why we recreated the Arpanet circa 1972-1973, and let you go through the 'Scenarios' yourself.
<br><br>

# Install
Clone, and run demo-run.sh. Inspect it for the things it does: (a) set up a local server, (b) a local client, both to get a terminal onto the web page, and (c) fire up the Arpanet itself.
<br><br>
Then, you can load the file arpanet_home.html into your browser. Or straight on to arpanet_terminal2.html if you want to skip the intro.
<br><br>
You might want to skip all the web stuff. A quick way straight onto your Arpanet is to run './do.sh 1'. That gets a TIP-like session; type @L 6 [return] and it will connect to MIT-MULTICS, type @L 126 [return] and it will connect to the Hilton conference-site KA host, type @L 134 [return] and it will connect to MIT-AI, or type @L 198 [return] and it will connect to MIT-ML.
<br><br>
The arpanet simulation consists of a network of IMP routers, which you can inspect and manage. The mini subdirectory contains the entire arpanet simulation, irrespective of the web server stuff. In ./mini, start by running ./impctl.py help. It will give you insight in how to play with the IMP farm. The hosts attached to the IMPs are started through ./mini/arpanet, they are started independently from the Arpanet IMP 'farm', but make sure you start ITS systems straight after starting their IMP. ITS is picky on when it wishes to hear from their IMP. Do 'screen -ls' to see the host systems themselves.
<br><br>
To stop, run stop-demo.sh.

<br>Dependencies: node.js, and Python websockets.
<br><br>
At the moment, do not expect much. We're building this up over the coming months.

# Structure

There is a fully formed but so far small Arpanet in ./mini. It consists of a network of (simh) simulated IMPs connecting to each other, and a number of (simh) PDP-10s and other machines. Many of the ones planned will run the reconstructed system software and applications from the period. The active public host set currently includes UCLA-NMC host 1 as a SIMH Sigma 7 CP-V system, MIT-MULTICS host 6 as a DPS8M/MR12.8 Multics system, MIT ITS hosts 70, 126, 134, and 198, Stanford/SU-AI host 11 running WAITS with restored PARRY support files, and the optional physical PiDP-10 path at host 41. Dormant local ITS disk sets remain available for additional MIT hosts, but they are not exposed by default. Host 11 is reached through a Linux bridge rather than through its own recovered WAITS NCP. The UCLA host 1 path is a browser terminal route to a real Sigma emulator and CP-V media, not recovered UCLA-NMC SEX media. Longer term, the hope is for deeper Multics NCP integration, PDP-11s, and perhaps even IBM 360s. It is early days yet. But the IMPs run reliably, connecting to make their network over simulated leased lines; and we're happy with progress :-)
<br><br>
A more or less stand-alone web project runs the project page as well as the terminal page. All it does is get a terminal from the ./mini directory projected on to your browser page. A python simh-server script brings you into the ./mini Arpanet wolrd, and a python terminal_client handles the data flow with the ./arpanet_terminal.html file. The HTML file with the terminal_client script can run the web site remotely from the server on which the ./mini Arpanet is running.
<br><br>
More to come.
